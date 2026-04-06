# Pond

A terminal replacement built around a structured render protocol.

Instead of character grids and escape sequences, programs send declarative render trees to a local renderer. The renderer draws native-feeling widgets. Remote servers run a lightweight runtime over SSH.

## Why

The terminal stack hasn't fundamentally changed since the 1970s. tmux, ncurses, TUIs — all workarounds against a protocol designed for teletypewriters.

Pond replaces that with a simple model: programs describe **what** to show, the renderer decides **how** to show it.

## Core idea

- **Streams**: Programs produce named, typed, live data. Any program can subscribe to any stream. This is the composition primitive — not pipes, not IPC, but typed observable data.
- **Render trees**: Programs describe what to show (tables, lists, text), the client decides how to draw it. Views bind to streams. Data updates constantly; the view structure rarely changes.
- **Effects**: Apps don't touch the world directly. They declare intent (`readDir`, `exec`, `watch`), the runtime fulfills it. This is what makes local and remote transparent.
- **Protocol**: The wire format between runtime and client. This is the project — everything else is an implementation detail.
- **Runtime**: Persistent daemon on servers — manages sessions, fulfills effects, holds state across disconnects.
- **Client**: Anything that speaks the protocol. A native app, a web page, a TUI — the protocol doesn't care.

## Programming model

A Pond app has two jobs:

1. **Describe what to show** — given current state, return a render tree
2. **Declare what should happen** — when the user interacts, emit effects

Everything else — rendering, layout, input, process management, file I/O, reconnection — is the platform's problem.

**Render trees**: Apps produce declarative widget trees, not escape codes. Widgets (lists, editors, tables, trees) know how to be themselves — scrolling, selection, focus are built in. The app says *what*, the platform decides *how*.

**Effects**: Apps don't touch the filesystem or spawn processes. They declare intent — `readDir`, `exec`, `watch`, `open` — and the runtime fulfills it. Results flow back as state updates, the render tree redraws. The app doesn't know or care whether the runtime is local or remote.

Effects are serializable — plain data, not function calls. `{"effect": "readDir", "path": "/home/user"}` is a message any language can produce and any runtime can fulfill. Because effects are data, the runtime can inspect, log, cache, replay, or deduplicate them. This also means effects are testable — assert that an app emits the right effects for a given state without actually performing them.

**The app is a guest**: A Pond app doesn't own the screen, the render loop, or system access. It's a guest inside a platform — like a web app in a browser. The platform handles layout, compositing, input routing, lifecycle, and persistence. Multiple apps can be on screen at once. Apps survive disconnects because the runtime holds their state.

## What it replaces

| Today | Pond |
|---|---|
| tmux | Client handles panes/tabs natively |
| vim over SSH | Local editor, remote files |
| SSH reconnects | Runtime persists, auto-reconnect on wake |
| ncurses TUIs | Declarative widgets (lists, tables, trees) |
| Scrollback in escape codes | Structured virtualized rendering |

## Docs

- [`docs/REFERENCE.md`](docs/REFERENCE.md) — technical references, data structures, proven systems to study

## Status

Design phase.

