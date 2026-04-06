# Pond

A terminal replacement built around a structured render protocol.

Instead of character grids and escape sequences, programs send declarative render trees to a local renderer. The renderer draws native-feeling widgets. Remote servers run a lightweight agent over SSH.

## Why

The terminal stack hasn't fundamentally changed since the 1970s. tmux, ncurses, TUIs — all workarounds against a protocol designed for teletypewriters.

Pond replaces that with a simple model: programs describe **what** to show, the renderer decides **how** to show it.

## Core idea

- **Protocol**: JSON render tree over length-prefixed binary frames over SSH. This is the project — everything else is an implementation detail.
- **Agent**: Persistent daemon on remote servers — manages PTYs, file I/O, sessions
- **Client**: Anything that speaks the protocol. A Tauri app, a web page, a native macOS app, a TUI — the protocol doesn't care. Pond defines the contract, not the renderer.
- **Optimistic editing**: Local-first rendering, async server sync. Zero typing latency even on remote servers.

## What it replaces

| Today | Pond |
|---|---|
| tmux | Client handles panes/tabs natively |
| vim over SSH | Local editor, remote files |
| SSH reconnects | Agent persists, auto-reconnect on wake |
| ncurses TUIs | Declarative widgets (lists, tables, trees) |
| Scrollback in escape codes | Structured virtualized rendering |

## Docs

- [`docs/REFERENCE.md`](docs/REFERENCE.md) — technical references, data structures, proven systems to study

## Status

Design phase.

