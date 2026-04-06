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

### The app is a guest

- Apps don't own the screen, the render loop, or system access
- The platform handles layout, compositing, input routing, lifecycle, persistence
- Multiple apps on screen at once
- Apps survive disconnects — the runtime holds their state

## Architecture

- **Protocol** — wire format between runtime and client. This is the project — everything else is an implementation detail.
- **Runtime** — persistent daemon on servers. Manages sessions, fulfills effects, holds state across disconnects.
- **Client** — anything that speaks the protocol. Native app, web page, TUI — doesn't matter.

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
