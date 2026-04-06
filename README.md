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


## Status

Design phase.
