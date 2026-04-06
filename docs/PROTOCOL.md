# Pond Wire Protocol v1

This document specifies the wire protocol between a Pond client and a Pond runtime. It is the complete reference for implementing either side.

## Transport

The wire protocol runs over a single SSH channel. The SSH connection provides authentication, encryption, compression, and keepalive. Pond does not define its own ping/pong or liveness mechanism.

## Framing

Every message is a length-prefixed frame:

```
+----------+----------+----------------------------+
| length   | encoding | payload                    |
| 4 bytes  | 1 byte   | `length - 1` bytes         |
+----------+----------+----------------------------+
```

- **length** (uint32, big-endian): byte count of encoding + payload. Does not include the 4 length bytes themselves. Minimum value is 1 (encoding byte, empty payload).
- **encoding** (uint8):
  - `0x01` = JSON (UTF-8)
  - `0x02` = MessagePack
- **payload**: the encoded message.

Both sides declare supported encodings in the handshake. All implementations must support JSON. MessagePack is optional. The runtime selects the encoding used for the session based on the intersection of both sides' capabilities, preferring MessagePack when both support it.

Maximum frame size: 16 MiB (16,777,216 bytes). A frame exceeding this is a protocol error; close the connection.

## Message envelope

Every decoded payload is a map with at least a `type` field (string). Messages scoped to an application carry an `app_id` field (string, client-assigned).

```json
{ "type": "render", "app_id": "editor-1", ... }
```

Unknown message types must be silently ignored. Unknown fields on known message types must be silently ignored. This is the forward-compatibility rule.

## Priority send queues

The runtime maintains three priority levels. When the send buffer can accept data, messages drain in this order:

1. **Control** -- `welcome`, `app_event`, `kill` responses
2. **Render** -- `render` messages
3. **Data** -- `data` messages

Within a priority level, messages are sent in the order they were enqueued. This ensures user-visible state changes and error notifications are never starved by bulk data.

The client is not required to implement priority queues. Client-to-runtime messages are small and infrequent enough that FIFO ordering is sufficient.

## Message type summary

| Type | Direction | Fields | Purpose |
|---|---|---|---|
| `hello` | client -> runtime | `version`, `encodings`, `capabilities`, `last_session_id` | Initiate handshake |
| `welcome` | runtime -> client | `version`, `encoding`, `session_id`, `apps` | Complete handshake, deliver session state |
| `launch` | client -> runtime | `app_id`, `command`, `args`, `env`, `cwd` | Start an application |
| `kill` | client -> runtime | `app_id`, `signal` | Terminate an application |
| `input` | client -> runtime | `app_id`, `event` | Send user input to an application |
| `subscribe` | client -> runtime | `stream`, `active` | Subscribe to or unsubscribe from a stream |
| `state_sync` | client -> runtime | `app_id`, `node_id`, `state`, `render_version` | Sync client-managed widget state to the runtime |
| `render` | runtime -> client | `app_id`, `tree`, `version`, `streams` | Deliver a full render tree with bound stream data |
| `data` | runtime -> client | `stream`, `seq`, `payload` | Deliver stream data |
| `app_event` | runtime -> client | `app_id`, `status`, `detail` | Report application lifecycle events |

10 message types total: 6 client-to-runtime, 4 runtime-to-client.

## Client-to-runtime messages

### `hello`

Sent once, immediately after the SSH channel is established. Must be the first frame on the connection.

```json
{
  "type": "hello",
  "version": 1,
  "encodings": ["json", "msgpack"],
  "capabilities": ["terminal"],
  "last_session_id": null
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `version` | uint | yes | Protocol version. Must be `1`. |
| `encodings` | [string] | yes | Supported encodings: `"json"`, `"msgpack"`. Must include `"json"`. |
| `capabilities` | [string] | yes | Client capabilities. `"terminal"` means the client can render the `terminal` widget. Empty array is valid. |
| `last_session_id` | string or null | yes | If reconnecting, the session ID from the previous `welcome`. `null` for a fresh connection. |

If `version` is unsupported, the runtime closes the connection (protocol error).

### `launch`

Start an application. The client assigns the `app_id`.

```json
{
  "type": "launch",
  "app_id": "editor-1",
  "command": "pond-editor",
  "args": ["main.rs"],
  "env": { "POND_THEME": "dark" },
  "cwd": "/home/user/project"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `app_id` | string | yes | Client-assigned identifier. Must be unique within the session. Must match `^[a-zA-Z0-9_-]{1,64}$`. |
| `command` | string | yes | Program to execute. |
| `args` | [string] | no | Command-line arguments. Default: `[]`. |
| `env` | map<string, string> | no | Additional environment variables. Default: `{}`. |
| `cwd` | string | no | Working directory. Default: runtime's cwd. |

The runtime responds with an `app_event` (status `"started"` or `"error"`). There is no separate launch-response message; the `app_id` is the correlation key.

### `input`

Send a user input event to an application.

```json
{
  "type": "input",
  "app_id": "editor-1",
  "event": {
    "kind": "key",
    "key": "Enter",
    "modifiers": ["ctrl"]
  }
}
```

```json
{
  "type": "input",
  "app_id": "editor-1",
  "event": {
    "kind": "select",
    "item_id": "file-main.rs",
    "render_version": 12
  }
}
```

```json
{
  "type": "input",
  "app_id": "editor-1",
  "event": {
    "kind": "activate",
    "item_id": "file-main.rs",
    "render_version": 12
  }
}
```

```json
{
  "type": "input",
  "app_id": "app-2",
  "event": {
    "kind": "mouse",
    "x": 10,
    "y": 5,
    "button": "left",
    "action": "press"
  }
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `app_id` | string | yes | Target application. |
| `event` | InputEvent | yes | The input event. |

**InputEvent** variants:

| `kind` | Additional fields | Description |
|---|---|---|
| `"key"` | `key` (string), `modifiers` ([string]) | Keyboard input. `key` is the key name (e.g. `"a"`, `"Enter"`, `"ArrowUp"`, `"F1"`, `"Tab"`). `modifiers` is zero or more of `"ctrl"`, `"alt"`, `"shift"`, `"meta"`. |
| `"text"` | `text` (string) | Raw text input (paste, IME commit). |
| `"select"` | `item_id` (string), `render_version` (uint) | Selection changed. Client-local highlight; server-authoritative meaning. |
| `"activate"` | `item_id` (string), `render_version` (uint) | Item activated (Enter, double-click). Round-trips to server. |
| `"mouse"` | `x` (uint), `y` (uint), `button` (string), `action` (string) | Mouse event. `button`: `"left"`, `"right"`, `"middle"`, `"scroll_up"`, `"scroll_down"`. `action`: `"press"`, `"release"`, `"move"`. |
| `"resize"` | `cols` (uint), `rows` (uint) | Viewport size changed for this application. |

`select` and `activate` reference `item_id` + `render_version`, not indices. This survives sorting, filtering, and streaming updates. If `render_version` is stale, the runtime may ignore the event or map it to the current tree.

### `kill`

Terminate an application.

```json
{
  "type": "kill",
  "app_id": "editor-1",
  "signal": "SIGTERM"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `app_id` | string | yes | Target application. |
| `signal` | string | no | Signal name. Default: `"SIGTERM"`. One of `"SIGTERM"`, `"SIGKILL"`, `"SIGINT"`, `"SIGHUP"`. |

The runtime responds with an `app_event` (status `"stopped"` or `"error"`).

### `subscribe`

Subscribe to or unsubscribe from a stream for out-of-band observation. This is for dashboards, inspectors, and debuggers. Streams bound in a render tree are delivered automatically; explicit `subscribe` is not needed for them.

```json
{
  "type": "subscribe",
  "stream": "app-2:pty",
  "active": true
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `stream` | string | yes | Stream address (see Stream Namespacing). |
| `active` | bool | yes | `true` to subscribe, `false` to unsubscribe. |

When `active` is `true`, the runtime begins sending `data` messages for the stream. When `active` is `false`, delivery stops. Subscribing to a nonexistent stream is not an error; delivery begins when the stream is created.

### `state_sync`

Sync client-managed widget state to the runtime. This is distinct from `input`: input events carry user intent (select, activate, key press), while `state_sync` carries the current value of client-owned interactive state (buffer contents, slider position, toggle value).

```json
{
  "type": "state_sync",
  "app_id": "editor-1",
  "node_id": "search-input",
  "render_version": 7,
  "state": {
    "value": "fn main",
    "cursor": 7,
    "selection": null
  }
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `app_id` | string | yes | Target application. |
| `node_id` | string | yes | The `id` of the widget whose state is being synced. |
| `render_version` | uint | yes | The render version the client is displaying. Used for stale-state detection. |
| `state` | map | yes | The widget's current client-managed state. Structure depends on the widget type. |

The runtime may ignore `state_sync` messages with a stale `render_version`.

When `state_sync` messages are sent depends on the widget's declared `sync` policy:

| Policy | Behavior |
|---|---|
| `"on-commit"` | Client sends state when the user commits (blur, Enter, explicit save). Default. |
| `"on-change"` | Client sends state on every change. |
| `{ "debounce": <ms> }` | Client sends state after `<ms>` milliseconds of inactivity. |

The sync policy is a hint from the runtime to the client. The client should respect it but the runtime must tolerate receiving `state_sync` at any time.

## Runtime-to-client messages

### `welcome`

Sent once in response to `hello`. Must be the first frame from the runtime.

```json
{
  "type": "welcome",
  "version": 1,
  "encoding": "msgpack",
  "session_id": "ses-a1b2c3",
  "apps": []
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `version` | uint | yes | Protocol version. `1`. |
| `encoding` | string | yes | Selected encoding for the rest of the session: `"json"` or `"msgpack"`. All subsequent frames (both directions) use this encoding. The `hello` and `welcome` themselves are always JSON. |
| `session_id` | string | yes | Stable session identifier. The client stores this and sends it as `last_session_id` on reconnect. |
| `apps` | [AppSnapshot] | yes | Current state of all running applications (empty on fresh connect). |

**AppSnapshot**:

```json
{
  "app_id": "editor-1",
  "status": "started",
  "command": "pond-editor",
  "args": ["main.rs"]
}
```

| Field | Type | Description |
|---|---|---|
| `app_id` | string | The application identifier. |
| `status` | string | Current status: `"started"`. |
| `command` | string | The command that was launched. |
| `args` | [string] | The arguments it was launched with. |

On reconnect (when the client sent a valid `last_session_id`), the `apps` array lists all running applications. Immediately after `welcome`, the runtime sends the current state for each running app: an `app_event` with status `"started"`, then a `render` message with the full tree and bound stream snapshots. The focused app is sent first.

### `render`

Deliver a full render tree for an application. In v1, every `render` is a complete tree replacement. There is no delta/patch mechanism.

```json
{
  "type": "render",
  "app_id": "editor-1",
  "version": 7,
  "tree": {
    "type": "column",
    "id": "root",
    "children": [
      {
        "type": "text",
        "id": "title",
        "props": { "content": "main.rs" }
      },
      {
        "type": "list",
        "id": "files",
        "bind": "editor-1:file-list",
        "props": {
          "items": [
            { "id": "file-main.rs", "label": "main.rs" },
            { "id": "file-lib.rs", "label": "lib.rs" }
          ],
          "selectable": true
        }
      }
    ]
  },
  "streams": {
    "editor-1:file-list": {
      "seq": 3,
      "payload": [
        { "id": "file-main.rs", "name": "main.rs", "size": 2048 },
        { "id": "file-lib.rs", "name": "lib.rs", "size": 512 }
      ]
    }
  }
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `app_id` | string | yes | The application this tree belongs to. |
| `version` | uint | yes | Monotonically increasing per-app render version. Continues across reconnects. Never resets. |
| `tree` | Widget | yes | The complete render tree. |
| `streams` | map<string, StreamSnapshot> | yes | Current snapshot of every stream bound in this tree. Keys are stream addresses. |

**StreamSnapshot**:

| Field | Type | Description |
|---|---|---|
| `seq` | uint | Current sequence number for this stream. |
| `payload` | any | Current value of the stream. |

The `streams` map ensures the client receives tree + data as one atomic frame. No blank flash, no race between tree and data.

**Widget** (recursive):

Every widget has at least `type` (string) and `id` (string). Widgets may have `props` (map), `bind` (string, stream address), `children` ([Widget]), and `fallback` (Widget, used when the client lacks a required capability).

Interactive widgets additionally carry:

| Field | Type | Description |
|---|---|---|
| `state` | map | Initial client-managed state. The client owns this state locally and syncs it back via `state_sync`. |
| `sync` | string or map | Sync policy: `"on-commit"` (default), `"on-change"`, or `{ "debounce": <ms> }`. |

Example — a text buffer with debounced sync for live search:

```json
{
  "type": "text-buffer",
  "id": "search-input",
  "props": { "placeholder": "Search...", "max_length": 256 },
  "state": { "value": "", "cursor": 0, "selection": null },
  "sync": { "debounce": 150 }
}
```

Example — a slider that syncs on every change for live preview:

```json
{
  "type": "slider",
  "id": "threshold",
  "props": { "min": 0, "max": 1, "step": 0.01 },
  "state": { "value": 0.5 },
  "sync": "on-change"
}
```

On reconnect, client-managed state is lost. The runtime re-sends the render tree with initial `state` values, and the client starts fresh. This is consistent with the snapshot-first reconnection model.

Core widget types:

- **Display**: `text`, `column`, `row` — no client state, render only.
- **Data-bound**: `list`, `table`, `tree` — bind to streams, support selection (always-local widget state per INPUT_LATENCY.md).
- **Interactive**: `text-buffer`, `input`, `slider`, `toggle`, `select` — carry client-managed `state` and a `sync` policy.
- **Legacy**: `terminal` — optional, see Terminal Widget section.

### `data`

Deliver a stream update.

```json
{
  "type": "data",
  "stream": "editor-1:diagnostics",
  "seq": 42,
  "payload": [
    { "line": 10, "severity": "error", "message": "expected `;`" }
  ]
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `stream` | string | yes | Stream address (see Stream Namespacing). |
| `seq` | uint | yes | Monotonically increasing per-stream sequence number. Continues across reconnects. Never resets. |
| `payload` | any | yes | The stream data. Structure depends on the stream's schema. |

The client uses `seq` to detect gaps and ordering. If a `data` message arrives with a `seq` that is not exactly `previous_seq + 1`, the client should treat it as a potential gap (messages may have been dropped under backpressure).

### `app_event`

Report application lifecycle changes.

```json
{
  "type": "app_event",
  "app_id": "editor-1",
  "status": "stopped",
  "detail": { "exit_code": 0 }
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `app_id` | string | yes | The application. |
| `status` | string | yes | One of `"started"`, `"stopped"`, `"error"`. |
| `detail` | map | no | Additional information, depends on status. |

**Status values:**

| Status | When sent | `detail` fields |
|---|---|---|
| `"started"` | App process launched successfully | `pid` (uint) |
| `"stopped"` | App process exited | `exit_code` (int), `signal` (string or null) |
| `"error"` | App failed to launch, or runtime error | `message` (string) |

There is no separate error message type. Application errors are reported through `app_event` with status `"error"`. Protocol-level errors (malformed frames, unsupported version) close the connection immediately.

## Stream namespacing

Stream addresses are strings with a colon-separated namespace:

```
<owner>:<name>
```

- **`<owner>`** is the `app_id` of the application that publishes the stream.
- **`<name>`** is a local name chosen by the application.

Examples:
- `editor-1:file-list` -- the file list published by `editor-1`
- `editor-1:diagnostics` -- compiler diagnostics published by `editor-1`
- `app-2:pty` -- the PTY cell-grid stream for a terminal app

Runtime introspection streams use the `runtime` namespace:
- `runtime:sessions`
- `runtime:programs`
- `runtime:streams`
- `runtime:wire`
- `runtime:effects`
- `runtime:connections`

The colon is reserved. Neither `<owner>` nor `<name>` may contain a colon. Stream addresses must match `^[a-zA-Z0-9_-]+:[a-zA-Z0-9_./-]+$`.

## Sequence numbers

Two kinds of sequence numbers exist:

- **Render version**: per-app, monotonically increasing, carried in `render.version`. Incremented each time the app produces a new render tree. Input events reference `render_version` to associate user actions with the tree state that was visible.
- **Stream seq**: per-stream, monotonically increasing, carried in `data.seq` and `render.streams[].seq`. Incremented each time the stream produces a new value.

Both continue across reconnects. They never reset. On reconnect, the client receives the current values and continues from there.

## Effects

Effects are server-internal. They never appear on the wire. Apps declare effects (read a file, spawn a process, watch a directory); the runtime fulfills them locally. The wire carries only the results: updated render trees, stream data, and lifecycle events.

## Terminal widget

The `terminal` widget renders legacy PTY programs. It is optional: clients that do not advertise `"terminal"` in their `hello` capabilities will receive the widget's `fallback` instead.

A `terminal` widget binds to a stream that carries `TerminalState`:

```json
{
  "cells": [
    { "x": 0, "y": 0, "text": "~", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
    { "x": 0, "y": 1, "text": "~", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null }
  ],
  "cursor": { "x": 0, "y": 0, "visible": true, "shape": "block" },
  "title": "vim",
  "mode": {
    "application_cursor": true,
    "application_keypad": false,
    "mouse_tracking": false,
    "bracketed_paste": true,
    "alternate_screen": true
  }
}
```

On first frame and on reconnect, `cells` contains every cell in the grid (full snapshot). On subsequent frames, `cells` contains only changed cells (diff).

`data` messages for terminal streams carry the same `TerminalState` structure. The `seq` number increments with each update.

For the complete cell, color, attribute, cursor, and mode specifications, see [`TERMINAL_WIDGET.md`](TERMINAL_WIDGET.md).

### Terminal input

When a `terminal` widget has focus, the client sends `input` events with `kind: "key"`, `kind: "text"`, or `kind: "mouse"`. The runtime translates these into the byte sequences the PTY program expects, accounting for the current terminal mode (application cursor, bracketed paste, etc.). The client never generates escape sequences.

### Terminal resize

When the client's viewport for a terminal app changes size, it sends:

```json
{
  "type": "input",
  "app_id": "vim-1",
  "event": { "kind": "resize", "cols": 120, "rows": 40 }
}
```

The runtime issues a `SIGWINCH` to the PTY process. The next `data` or `render` message will reflect the new grid dimensions.

## Reconnection

Reconnection is snapshot-first. The runtime holds all application state. When a client reconnects, it receives the full current state immediately. No deltas, no replay logs, no progressive restoration.

### Reconnection sequence

```
Client                                   Runtime
  |                                         |
  |  [SSH connection established]           |
  |                                         |
  |  hello {                                |
  |    version: 1,                          |
  |    encodings: ["json","msgpack"],       |
  |    capabilities: ["terminal"],          |
  |    last_session_id: "ses-a1b2c3"   -->  |
  |  }                                      |
  |                                         |  (validates session_id,
  |                                         |   finds 2 running apps:
  |                                         |   editor-1 (focused),
  |                                         |   vim-1)
  |                                         |
  |                                    <--  |  welcome {
  |                                         |    version: 1,
  |                                         |    encoding: "msgpack",
  |                                         |    session_id: "ses-a1b2c3",
  |                                         |    apps: [
  |                                         |      {app_id:"editor-1", status:"started", ...},
  |                                         |      {app_id:"vim-1", status:"started", ...}
  |                                         |    ]
  |                                         |  }
  |                                         |
  |                                    <--  |  app_event { app_id:"editor-1",
  |                                         |    status:"started", detail:{pid:1234} }
  |                                         |
  |                                    <--  |  render { app_id:"editor-1",
  |                                         |    version:42, tree:{...},
  |                                         |    streams:{ "editor-1:file-list":{seq:18,...} }
  |                                         |  }
  |                                         |
  |                                    <--  |  app_event { app_id:"vim-1",
  |                                         |    status:"started", detail:{pid:1235} }
  |                                         |
  |                                    <--  |  render { app_id:"vim-1",
  |                                         |    version:7, tree:{type:"terminal",...},
  |                                         |    streams:{ "vim-1:pty":{seq:390,...} }
  |                                         |  }
  |                                         |
  |  [session fully restored]               |
```

Key properties:
- The focused app is sent first.
- Sequence numbers (`version`, `seq`) continue from where they were. They do not reset.
- The `render` message's `streams` map contains full snapshots of all bound data.
- Client-owned widget state (scroll position, selection highlight, input field contents) is lost. The client starts from the server-authoritative state.
- If `last_session_id` does not match any active session, the runtime sends `welcome` with a new `session_id` and an empty `apps` array (fresh session).

## Session transcript: native Pond app

A complete session: connect, launch an app, receive renders, data flows, user input, kill the app, disconnect, reconnect.

```
# 1. Connect
# =========

Client -> Runtime:
{
  "type": "hello",
  "version": 1,
  "encodings": ["json"],
  "capabilities": ["terminal"],
  "last_session_id": null
}

Runtime -> Client:
{
  "type": "welcome",
  "version": 1,
  "encoding": "json",
  "session_id": "ses-x7f9k2",
  "apps": []
}

# 2. Launch app
# =============

Client -> Runtime:
{
  "type": "launch",
  "app_id": "editor-1",
  "command": "pond-editor",
  "args": ["src/main.rs"],
  "env": {},
  "cwd": "/home/user/project"
}

Runtime -> Client:
{
  "type": "app_event",
  "app_id": "editor-1",
  "status": "started",
  "detail": { "pid": 4821 }
}

# 3. First render
# ===============

Runtime -> Client:
{
  "type": "render",
  "app_id": "editor-1",
  "version": 1,
  "tree": {
    "type": "column",
    "id": "root",
    "children": [
      {
        "type": "text",
        "id": "header",
        "props": { "content": "pond-editor: src/main.rs" }
      },
      {
        "type": "list",
        "id": "file-tree",
        "bind": "editor-1:file-list",
        "props": {
          "items": [
            { "id": "f-main", "label": "src/main.rs" },
            { "id": "f-lib", "label": "src/lib.rs" }
          ],
          "selectable": true
        }
      },
      {
        "type": "text",
        "id": "editor-pane",
        "bind": "editor-1:active-file",
        "props": { "content": "" }
      }
    ]
  },
  "streams": {
    "editor-1:file-list": {
      "seq": 1,
      "payload": [
        { "id": "f-main", "name": "src/main.rs", "size": 1024 },
        { "id": "f-lib", "name": "src/lib.rs", "size": 256 }
      ]
    },
    "editor-1:active-file": {
      "seq": 1,
      "payload": { "path": "src/main.rs", "content": "fn main() {\n    println!(\"hello\");\n}" }
    }
  }
}

# 4. Stream data update (file watcher detects a new file)
# =======================================================

Runtime -> Client:
{
  "type": "data",
  "stream": "editor-1:file-list",
  "seq": 2,
  "payload": [
    { "id": "f-main", "name": "src/main.rs", "size": 1024 },
    { "id": "f-lib", "name": "src/lib.rs", "size": 256 },
    { "id": "f-util", "name": "src/util.rs", "size": 128 }
  ]
}

# 5. Render update (app redraws with new file in list)
# ====================================================

Runtime -> Client:
{
  "type": "render",
  "app_id": "editor-1",
  "version": 2,
  "tree": {
    "type": "column",
    "id": "root",
    "children": [
      {
        "type": "text",
        "id": "header",
        "props": { "content": "pond-editor: src/main.rs" }
      },
      {
        "type": "list",
        "id": "file-tree",
        "bind": "editor-1:file-list",
        "props": {
          "items": [
            { "id": "f-main", "label": "src/main.rs" },
            { "id": "f-lib", "label": "src/lib.rs" },
            { "id": "f-util", "label": "src/util.rs" }
          ],
          "selectable": true
        }
      },
      {
        "type": "text",
        "id": "editor-pane",
        "bind": "editor-1:active-file",
        "props": { "content": "" }
      }
    ]
  },
  "streams": {
    "editor-1:file-list": {
      "seq": 2,
      "payload": [
        { "id": "f-main", "name": "src/main.rs", "size": 1024 },
        { "id": "f-lib", "name": "src/lib.rs", "size": 256 },
        { "id": "f-util", "name": "src/util.rs", "size": 128 }
      ]
    },
    "editor-1:active-file": {
      "seq": 1,
      "payload": { "path": "src/main.rs", "content": "fn main() {\n    println!(\"hello\");\n}" }
    }
  }
}

# 6. User selects a file (client highlights immediately)
# ======================================================

Client -> Runtime:
{
  "type": "input",
  "app_id": "editor-1",
  "event": {
    "kind": "select",
    "item_id": "f-lib",
    "render_version": 2
  }
}

# 7. User activates the file (double-click or Enter)
# ===================================================

Client -> Runtime:
{
  "type": "input",
  "app_id": "editor-1",
  "event": {
    "kind": "activate",
    "item_id": "f-lib",
    "render_version": 2
  }
}

# 8. App responds with new render (active file changed)
# =====================================================

Runtime -> Client:
{
  "type": "render",
  "app_id": "editor-1",
  "version": 3,
  "tree": {
    "type": "column",
    "id": "root",
    "children": [
      {
        "type": "text",
        "id": "header",
        "props": { "content": "pond-editor: src/lib.rs" }
      },
      {
        "type": "list",
        "id": "file-tree",
        "bind": "editor-1:file-list",
        "props": {
          "items": [
            { "id": "f-main", "label": "src/main.rs" },
            { "id": "f-lib", "label": "src/lib.rs" },
            { "id": "f-util", "label": "src/util.rs" }
          ],
          "selectable": true
        }
      },
      {
        "type": "text",
        "id": "editor-pane",
        "bind": "editor-1:active-file",
        "props": { "content": "" }
      }
    ]
  },
  "streams": {
    "editor-1:file-list": {
      "seq": 2,
      "payload": [
        { "id": "f-main", "name": "src/main.rs", "size": 1024 },
        { "id": "f-lib", "name": "src/lib.rs", "size": 256 },
        { "id": "f-util", "name": "src/util.rs", "size": 128 }
      ]
    },
    "editor-1:active-file": {
      "seq": 2,
      "payload": { "path": "src/lib.rs", "content": "pub fn add(a: i32, b: i32) -> i32 {\n    a + b\n}" }
    }
  }
}

# 9. Subscribe to out-of-band stream (e.g. inspector)
# ====================================================

Client -> Runtime:
{
  "type": "subscribe",
  "stream": "runtime:programs",
  "active": true
}

Runtime -> Client:
{
  "type": "data",
  "stream": "runtime:programs",
  "seq": 1,
  "payload": [
    { "id": "editor-1", "name": "pond-editor", "pid": 4821, "state": "running", "cpu": 0.3, "mem": 12582912 }
  ]
}

# 10. Kill the app
# ================

Client -> Runtime:
{
  "type": "kill",
  "app_id": "editor-1"
}

Runtime -> Client:
{
  "type": "app_event",
  "app_id": "editor-1",
  "status": "stopped",
  "detail": { "exit_code": 0, "signal": "SIGTERM" }
}

# 11. Unsubscribe from out-of-band stream
# ========================================

Client -> Runtime:
{
  "type": "subscribe",
  "stream": "runtime:programs",
  "active": false
}

# 12. Disconnect (SSH drops)
# ==========================
# No protocol message. The TCP connection is lost.
# The runtime keeps all app state. editor-1 was already killed,
# but if it were still running, it would continue.

# 13. Reconnect
# =============

Client -> Runtime:
{
  "type": "hello",
  "version": 1,
  "encodings": ["json"],
  "capabilities": ["terminal"],
  "last_session_id": "ses-x7f9k2"
}

# No running apps (editor-1 was killed), so welcome has empty apps:
Runtime -> Client:
{
  "type": "welcome",
  "version": 1,
  "encoding": "json",
  "session_id": "ses-x7f9k2",
  "apps": []
}
```

## Session transcript: PTY app (vim)

Launch vim, receive terminal renders, send keystrokes, observe cell diffs.

```
# 1. Launch vim
# =============

Client -> Runtime:
{
  "type": "launch",
  "app_id": "vim-1",
  "command": "vim",
  "args": ["main.rs"],
  "cwd": "/home/user/project"
}

Runtime -> Client:
{
  "type": "app_event",
  "app_id": "vim-1",
  "status": "started",
  "detail": { "pid": 5102 }
}

# 2. First render -- terminal widget with full cell grid
# =======================================================
# The runtime spawned vim in a PTY, fed output through a server-side VTE,
# and produced a render tree with a terminal widget.

Runtime -> Client:
{
  "type": "render",
  "app_id": "vim-1",
  "version": 1,
  "tree": {
    "type": "terminal",
    "id": "term",
    "bind": "vim-1:pty",
    "fallback": {
      "type": "text",
      "id": "term-fallback",
      "props": { "content": "Legacy terminal app (requires terminal-capable client)" }
    }
  },
  "streams": {
    "vim-1:pty": {
      "seq": 1,
      "payload": {
        "cells": [
          { "x": 0, "y": 0, "text": "f", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
          { "x": 1, "y": 0, "text": "n", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
          { "x": 2, "y": 0, "text": " ", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
          { "x": 3, "y": 0, "text": "m", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
          { "x": 4, "y": 0, "text": "a", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
          { "x": 5, "y": 0, "text": "i", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
          { "x": 6, "y": 0, "text": "n", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
          { "x": 7, "y": 0, "text": "(", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
          { "x": 8, "y": 0, "text": ")", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
          { "x": 9, "y": 0, "text": " ", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
          { "x": 10, "y": 0, "text": "{", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
          { "x": 0, "y": 1, "text": " ", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
          { "x": 0, "y": 23, "text": "~", "width": 1, "fg": { "kind": "indexed", "value": 4 }, "bg": null, "attrs": 0, "url": null },
          { "x": 0, "y": 24, "text": "\"", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
          { "x": 1, "y": 24, "text": "m", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
          { "x": 2, "y": 24, "text": "a", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
          { "x": 3, "y": 24, "text": "i", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
          { "x": 4, "y": 24, "text": "n", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
          { "x": 5, "y": 24, "text": ".", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
          { "x": 6, "y": 24, "text": "r", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
          { "x": 7, "y": 24, "text": "s", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null }
        ],
        "cursor": { "x": 0, "y": 0, "visible": true, "shape": "block" },
        "title": "vim - main.rs",
        "mode": {
          "application_cursor": true,
          "application_keypad": false,
          "mouse_tracking": false,
          "bracketed_paste": true,
          "alternate_screen": true
        }
      }
    }
  }
}

# (cells above abbreviated -- a real frame contains all 80x25 = 2000 cells)

# 3. User presses 'j' to move cursor down
# =========================================

Client -> Runtime:
{
  "type": "input",
  "app_id": "vim-1",
  "event": { "kind": "key", "key": "j", "modifiers": [] }
}

# 4. Cell diff -- only the changed cells are sent
# ================================================
# Vim moved the cursor down one line. The VTE detected
# the change and the runtime sends only the affected cells.

Runtime -> Client:
{
  "type": "data",
  "stream": "vim-1:pty",
  "seq": 2,
  "payload": {
    "cells": [
      { "x": 0, "y": 0, "text": "f", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
      { "x": 0, "y": 1, "text": " ", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null }
    ],
    "cursor": { "x": 0, "y": 1, "visible": true, "shape": "block" },
    "title": null,
    "mode": {
      "application_cursor": true,
      "application_keypad": false,
      "mouse_tracking": false,
      "bracketed_paste": true,
      "alternate_screen": true
    }
  }
}

# 5. User presses 'i' to enter insert mode
# ==========================================

Client -> Runtime:
{
  "type": "input",
  "app_id": "vim-1",
  "event": { "kind": "key", "key": "i", "modifiers": [] }
}

# 6. Vim enters insert mode -- cursor shape changes, status line updates
# ======================================================================

Runtime -> Client:
{
  "type": "data",
  "stream": "vim-1:pty",
  "seq": 3,
  "payload": {
    "cells": [
      { "x": 0, "y": 24, "text": "-", "width": 1, "fg": null, "bg": null, "attrs": 1, "url": null },
      { "x": 1, "y": 24, "text": "-", "width": 1, "fg": null, "bg": null, "attrs": 1, "url": null },
      { "x": 3, "y": 24, "text": "I", "width": 1, "fg": null, "bg": null, "attrs": 1, "url": null },
      { "x": 4, "y": 24, "text": "N", "width": 1, "fg": null, "bg": null, "attrs": 1, "url": null },
      { "x": 5, "y": 24, "text": "S", "width": 1, "fg": null, "bg": null, "attrs": 1, "url": null },
      { "x": 6, "y": 24, "text": "E", "width": 1, "fg": null, "bg": null, "attrs": 1, "url": null },
      { "x": 7, "y": 24, "text": "R", "width": 1, "fg": null, "bg": null, "attrs": 1, "url": null },
      { "x": 8, "y": 24, "text": "T", "width": 1, "fg": null, "bg": null, "attrs": 1, "url": null }
    ],
    "cursor": { "x": 4, "y": 1, "visible": true, "shape": "bar" },
    "title": null,
    "mode": {
      "application_cursor": true,
      "application_keypad": false,
      "mouse_tracking": false,
      "bracketed_paste": true,
      "alternate_screen": true
    }
  }
}

# 7. User types "hello" in insert mode
# ======================================

Client -> Runtime:
{
  "type": "input",
  "app_id": "vim-1",
  "event": { "kind": "text", "text": "hello" }
}

# 8. Cells update as text is inserted
# =====================================

Runtime -> Client:
{
  "type": "data",
  "stream": "vim-1:pty",
  "seq": 4,
  "payload": {
    "cells": [
      { "x": 4, "y": 1, "text": "h", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
      { "x": 5, "y": 1, "text": "e", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
      { "x": 6, "y": 1, "text": "l", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
      { "x": 7, "y": 1, "text": "l", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
      { "x": 8, "y": 1, "text": "o", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null }
    ],
    "cursor": { "x": 9, "y": 1, "visible": true, "shape": "bar" },
    "title": null,
    "mode": {
      "application_cursor": true,
      "application_keypad": false,
      "mouse_tracking": false,
      "bracketed_paste": true,
      "alternate_screen": true
    }
  }
}

# 9. User presses Escape to return to normal mode
# ================================================

Client -> Runtime:
{
  "type": "input",
  "app_id": "vim-1",
  "event": { "kind": "key", "key": "Escape", "modifiers": [] }
}

Runtime -> Client:
{
  "type": "data",
  "stream": "vim-1:pty",
  "seq": 5,
  "payload": {
    "cells": [
      { "x": 0, "y": 24, "text": " ", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
      { "x": 1, "y": 24, "text": " ", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
      { "x": 3, "y": 24, "text": " ", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
      { "x": 4, "y": 24, "text": " ", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
      { "x": 5, "y": 24, "text": " ", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
      { "x": 6, "y": 24, "text": " ", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
      { "x": 7, "y": 24, "text": " ", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null },
      { "x": 8, "y": 24, "text": " ", "width": 1, "fg": null, "bg": null, "attrs": 0, "url": null }
    ],
    "cursor": { "x": 8, "y": 1, "visible": true, "shape": "block" },
    "title": null,
    "mode": {
      "application_cursor": true,
      "application_keypad": false,
      "mouse_tracking": false,
      "bracketed_paste": true,
      "alternate_screen": true
    }
  }
}

# 10. Kill vim
# ============

Client -> Runtime:
{
  "type": "kill",
  "app_id": "vim-1"
}

Runtime -> Client:
{
  "type": "app_event",
  "app_id": "vim-1",
  "status": "stopped",
  "detail": { "exit_code": 0, "signal": "SIGTERM" }
}
```

## Protocol errors

Protocol errors are fatal. The connection is closed immediately with no error message on the wire. Conditions that are protocol errors:

- First frame from client is not `hello`.
- First frame from runtime is not `welcome`.
- Unsupported `version` in `hello`.
- Frame exceeds 16 MiB.
- Frame payload cannot be decoded as the negotiated encoding.
- Decoded payload is not a map or lacks a `type` field.

Application-level errors (bad `app_id`, launch failure, etc.) are not protocol errors. They are reported via `app_event` with status `"error"`.

## Implementation notes

### Client-assigned `app_id`

The client generates `app_id` values. This eliminates request/response correlation. The client does not need to wait for a response before referencing an app: it can send `launch` followed immediately by `input` for the same `app_id`. If the launch fails, the input is silently dropped.

### Bound streams vs. explicit subscribe

Streams referenced by a `bind` field in a render tree are delivered automatically. The runtime tracks which streams are bound in each app's current tree and delivers `data` messages for them. When a render tree no longer references a stream, delivery stops.

`subscribe` is only for out-of-band observation: an inspector watching another app's stream, a dashboard subscribing to `runtime:programs`, etc. Most clients never send `subscribe`.

### Output caps

The runtime caps buffered output per application at approximately 64 KB. If an app produces data faster than the wire can drain it, the runtime drops intermediate frames and sends the latest state. Since `render` is full-tree replacement and `data` carries complete stream values, dropping intermediate frames is safe -- the client always receives a consistent latest state.

### `state_sync` vs `input`

Both flow from client to runtime, but they serve different purposes:

- `input` carries user intent: "select this item", "activate this row", "press this key." The runtime interprets the meaning.
- `state_sync` carries interaction data: "the buffer now contains X", "the slider is at 0.85." The client owns the state and reports its current value.

A text editor example: every keystroke updates the buffer locally (no wire message). The `state_sync` fires per the sync policy (debounced, on-change, or on-commit). When the user presses Ctrl+S, that's an `input` event with `kind: "key"` that the app interprets as "save" — or an effect, depending on the app's design. The buffer contents arrived via `state_sync`; the save intent arrived via `input`.

### Encoding negotiation

The `hello` and `welcome` messages are always encoded as JSON, regardless of the negotiated encoding. This ensures any implementation can parse the handshake. Starting from the first frame after `welcome` (in both directions), all messages use the encoding specified in `welcome.encoding`.
