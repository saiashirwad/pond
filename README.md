# Pond

A terminal replacement built around a structured render protocol.

The terminal stack hasn't changed since the 1970s. Pond replaces it: programs describe **what** to show, the platform decides **how**.

## How it works

A Pond app has two jobs:

1. **Describe what to show** — return a render tree
2. **Declare what should happen** — emit effects

Everything else is the platform's problem.

### Render trees

- Apps produce declarative widget trees, not escape codes
- Widgets (lists, editors, tables, trees) handle their own scrolling, selection, focus
- Views bind to **streams** — named, typed, live data that any program can publish or subscribe to
- Data updates constantly; the view structure rarely changes

### Effects

- Apps don't touch the filesystem or spawn processes — they declare intent
- `readDir`, `exec`, `watch`, `open` — the runtime fulfills them
- Results flow back as state updates, the render tree redraws
- The app doesn't know or care if the runtime is local or remote
- Effects are serializable — plain data, not function calls
  - Any language can produce them
  - The runtime can inspect, log, cache, replay, or deduplicate them
  - Testable — assert an app emits the right effects without performing them

### Composition

- Programs compose by subscribing to each other's streams — not by piping text
- Streams are named, typed, and live — multiple consumers at once, no parsing
- A transform is just a program that subscribes to a stream and emits a new one
- Each intermediate stream is independently observable and subscribable
- No process spawning per query — subscriptions are persistent, data just flows

### The app is a guest

- Apps don't own the screen, the render loop, or system access
- The platform handles layout, compositing, input routing, lifecycle, persistence
- Multiple apps on screen at once
- Apps survive disconnects — the runtime holds their state

## Architecture

```
┌─────── Server ──────────────────┐
│                                  │
│  Apps ←──effects──→ Runtime      │
│        (local pipes)             │
│                                  │
└──────────────┬───────────────────┘
               │ SSH
               │ (render trees, data, input events)
┌──────────────┴───────────────────┐
│            Client                 │
└───────────────────────────────────┘
```

- **Apps + Runtime** live on the server. Effects (readDir, exec, watch) are fulfilled locally — they never cross the wire.
- **The protocol** carries only the results: render trees, stream data, and input events. This is the project — everything else is an implementation detail.
- **The client** receives render trees and data, sends input events back. It never sees effects. It's a view with a keyboard.

### Runtime

- Single static binary, no dependencies — uploaded over SSH on first connect, zero setup
- Does everything apps can't: fulfills effects, manages sessions, wraps legacy programs (bash, vim) in PTYs
- Holds state across disconnects — when you reconnect, it sends back structured state, not a character grid
- The client gets actual data, render trees, and session structure — redraws natively
- Think tmux, but the server keeps real state instead of a grid of characters

### Client

- Receives: render trees, data updates, program lifecycle events
- Sends: input events (keys, clicks), subscriptions, session management
- Roughly 6-7 message types in each direction — small, fixed, understandable
- Swappable — any client works, no app knows the difference

## What it replaces

| Today | Pond |
|---|---|
| tmux | Client handles panes/tabs natively |
| vim over SSH | Local editor, remote files |
| SSH reconnects | Runtime persists, auto-reconnect on wake |
| ncurses TUIs | Declarative widgets (lists, tables, trees) |
| Scrollback in escape codes | Structured virtualized rendering |


## Open questions

- **Are effects and streams one lifecycle or two?**
  - An `exec` effect completes instantly (process started) but its stdout stream runs for hours
  - A `watch` is ephemeral; an `exec` creates a durable resource (a PID)
  - If stream termination is coupled to effect completion, streams can't outlive their spawning effect, one effect can't produce multiple independent streams, and reconnection to running processes becomes impossible
- **How does the protocol evolve without breaking clients?**
  - If unknown message types are fatal, adding any new type breaks every deployed client
  - If they're silently ignored, old clients coexist with new runtimes
  - The harder question: when do you need a capability flag (behavioral change, like "I understand render diffs") vs. just adding a field to an existing message (data change, which MessagePack handles for free)?
- **What can an app do by default?**
  - Right now any app can `exec` arbitrary commands, read any path, subscribe to any stream — zero isolation
  - Should apps declare capabilities upfront (Android permission model)?
  - Should the default be CWD-only for reads, nothing for writes and exec unless explicitly granted?
- **How does reconnection transfer state?**
  - This is what makes Pond different from tmux (character grid replay)
  - It requires version-tagged render trees, sequence-numbered streams, and a protocol for deciding delta vs. snapshot
  - Should input events carry the render version they were based on so the server can detect stale operations?
  - What happens to effects that completed while the client was disconnected?
- **Is SSH's flow control sufficient?**
  - A single fast producer (e.g. `find /` streaming results) fills the SSH send buffer and freezes every program's render updates plus the user's keystroke latency
  - TCP treats all bytes equally
  - Does the protocol need its own priority queues (input before renders, renders before bulk data), per-stream throttling, and window-based flow control for large transfers?
- **How are PTY programs represented on the wire?**
  - Raw escape sequences to the client (like xterm.js) or structured cell grids from a server-side VTE?
  - Raw bytes mean every client must embed a terminal emulator
  - Cell grids mean the protocol must specify the cell format as a first-class commitment — but give structured reconnection
  - Server-side VTE locks the protocol's capability ceiling to the VTE library's ceiling
- **Where does input translation happen?**
  - For native Pond widgets the client can translate "user pressed j" into "select row 4" with zero round trips
  - For PTY programs the runtime must translate structured key events back to escape sequences, which requires tracking terminal mode state
  - These are fundamentally different paths through the same protocol
- **Is layout in the protocol?**
  - Multiple apps visible at once — does the protocol carry where each app is on screen, or does the client own layout entirely?
  - If the client owns it, resize events need per-program viewport sizes
  - If the protocol owns it, every client must agree on a layout model
- **How do virtualized lists work over a wire?**
  - A 10,000-row table where only 50 rows are visible — locally (React, Flutter) this is solved, over a wire it isn't
  - The server must materialize rows fast enough for 60Hz scrolling, with pre-fetch to absorb round-trip latency
  - No existing wire protocol solves this
- **JSON or MessagePack by default?**
  - JSON is debuggable, universal, and requires no library — `echo '{"type":"hello","version":1}' | nc -U ~/.pond/runtime.sock` just works
  - MessagePack is 34% smaller but unreadable without tools
  - SSH compresses both — does v1 ship debuggable and optimize later, or start binary?
- **How does SSH bootstrap actually work?**
  - Shell startup banners and `~/.bashrc` output corrupt framing
  - The runtime must daemonize without dying on SIGHUP when SSH drops
  - Binary upload (5-10MB) over a slow uplink blocks everything until complete

## Findings

- **No distributed systems machinery needed.** One server, one client, ordered transport, server is authority. No CRDTs, no vector clocks, no consensus. Revisit only for multi-user collaboration
- **Reconnect is the killer feature.** Tmux replays a character grid (~50-200KB every time). Pond sends versioned deltas (~2KB). But only if versioning and snapshot-or-delta selection are nailed
- **Steady-state monitoring is 100-375x more bandwidth-efficient** than terminal redraws. A 1Hz htop goes from ~25KB/sec to ~80B/sec after the initial render tree
- **Program identity comes from the connection, not the message body.** Each app communicates over its own pipe — the runtime stamps program identity from the file descriptor. Apps can't spoof each other
- **PTY programs are fundamentally more expensive** than native Pond apps — per-keystroke overhead is 55x (55 bytes vs 1 byte), plus VTE parsing and cell diffing on every frame

## Status

Design phase.
