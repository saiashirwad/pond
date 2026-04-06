# Design

A Pond app is a function from state to UI, plus declared effects for anything that touches the world.

## Two jobs

1. **Describe what to show** — given current state, return a render tree
2. **Declare what should happen** — when the user interacts, emit effects

Everything else — rendering, layout, input, process management, file I/O, reconnection — is the platform's problem.

## Render tree

Apps produce declarative widget trees, not escape codes. Widgets (lists, editors, tables, trees) know how to be themselves — scrolling, selection, focus are built in. The app says *what*, the platform decides *how*.

## Effects

Apps don't touch the filesystem or spawn processes. They declare intent — `readDir`, `exec`, `watch`, `open` — and the runtime fulfills it. The app doesn't know or care whether the runtime is local or remote. This is what makes the programming model work over SSH without the author thinking about it.

## The app is a guest

A Pond app doesn't own the screen, the render loop, or system access. It's a guest inside a platform — like a web app in a browser. The platform handles layout, compositing, input routing, lifecycle, and persistence. Multiple apps can be on screen at once. Apps survive disconnects because the runtime holds their state.

## Why

The DX gap between writing a terminal app and writing a web app is enormous. Pond closes it — not by putting a browser in the terminal, but by giving programs the same declarative, effect-driven model that makes web development productive.
