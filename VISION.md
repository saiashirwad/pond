# Vision

Pond is a structured interface protocol — a universal contract for how programs describe what they want to show, what data they have, and what work they want done.

## Effects and streams as agent primitives

Agents don't need better GUIs. They need better primitives for interacting with the world. Pond's effect system and typed streams provide that.

- Serializable effects mean every agent action is logged, inspectable, and replayable by construction
- Runtime interception means effects can be refused before they happen — the precondition for agent safety that most systems make structurally difficult
- Typed stream composition gives multi-step workflows real structure instead of stdout parsing
- Shared sessions let a human and an agent occupy the same runtime — the human sees a GUI, the agent sees typed data

An agent is just another program. No special mode needed.

## Shared semantic workspaces

The runtime doesn't care who's looking. Render trees and streams go to "a client" — one client or five.

- Two people connect to the same runtime with independent viewports and selections. Not screen sharing — a shared workspace with structured state.
- A human and an AI agent share a session. Same state, different consumption.
- Live handoff is reconnection. Async review is inspecting queued effects. Audit trails are subscribing to `runtime/effects`.

## Composable infrastructure

Every DevOps tool today has its own dashboard, API, and query language. Pond replaces that with one contract: typed streams in, effects out.

- Deployment pipelines as composable app sessions — each stage publishes typed streams, any client renders them
- Incident response as structured stream subscription + effect issuance, with the timeline captured by construction
- Fleet management as one client composing streams from many runtimes
- Live infrastructure state instead of plan-then-apply

## Write once, render anywhere

One program, many surfaces. A render tree renders natively on macOS, web, TUI, mobile. The app author wrote one thing.

- Remote is the primary case — an iPad on a headless dev server gets the same fidelity as a desktop client
- Composition replaces integration glue — typed streams connect tools without middleware
- The runtime exposes its own state as streams — monitoring, debugging, and administration are just apps

## Serializable sessions

Every Pond session is an artifact. Effects are replayable. Streams are observable. Render trees are inspectable.

- Time-travel debugging — replay a session and watch every state change
- Testable programs — assert which effects an app emits without performing them
- Accessibility by construction — clients get structured render trees, not pixels
- AI interpretability by construction — an agent's perceptions, intentions, and expressions are a typed, replayable record
