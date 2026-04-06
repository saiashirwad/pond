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

A Pond app is a function from state to UI. Describe what to show, declare what should happen — the platform handles everything else. No escape codes, no render loops, no manual input handling.

System interactions are **effects** — declared intent, not direct calls. An app doesn't read a directory or spawn a process. It declares `readDir(path)` or `exec(cmd)`, and the runtime fulfills it. Results flow back as state updates, the render tree redraws. The app never touches the filesystem, manages a PTY, or deals with async plumbing. This is what makes local and remote feel identical — the runtime handles it, wherever it's running.

See [`DESIGN.md`](DESIGN.md) for more.

## What it replaces

| Today | Pond |
|---|---|
| tmux | Client handles panes/tabs natively |
| vim over SSH | Local editor, remote files |
| SSH reconnects | Runtime persists, auto-reconnect on wake |
| ncurses TUIs | Declarative widgets (lists, tables, trees) |
| Scrollback in escape codes | Structured virtualized rendering |

## Docs

- [`DESIGN.md`](DESIGN.md) — programming model: state → UI, declared effects
- [`docs/REFERENCE.md`](docs/REFERENCE.md) — technical references, data structures, proven systems to study

## Status

Design phase.

