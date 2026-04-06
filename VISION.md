# Vision

Pond started as a terminal replacement. It isn't one.

It's a structured interface protocol — a universal contract for how programs describe what they want to show, what data they have, and what work they want done. The terminal was just the first thing that made the problem visible.

## AI agents

The agent win is not "structured GUIs instead of screenshots." Agents don't need better GUIs — the industry is converging on tool-calling protocols, function calling, and SDKs. Most agent tasks (code editing, file management, data analysis) already have structured interfaces.

The real win is **effects and streams as agent primitives.**

- **Serializable effects** mean every agent action is logged, inspectable, and replayable by construction. Not best-effort logging bolted on afterward — completeness by architecture.
- **Runtime interception** means effects can be refused before they happen. This is the precondition for agent safety — not safety "for free," but safety that's *possible to implement correctly*, which most systems make structurally difficult.
- **Typed stream composition** means multi-step workflows get real structure. An agent orchestrating build-then-test-then-deploy subscribes to typed streams between stages, not parsing stdout.
- **Shared sessions** are where the render tree matters for agents. A human and an agent on the same runtime see the same structured state — the human as a GUI, the agent as typed data. Teaching, pair debugging, supervised autonomy.

Where Pond genuinely helps agents: multi-step workflows, system monitoring, teaching/tutoring, sysadmin. Where it doesn't matter: code editing, file management, data analysis, web browsing — these already have better-than-GUI interfaces for agents.

An agent is just another program. No special mode needed. But the value is the effect system and stream composition, not the render tree.

## Collaboration

The single-user design is already the degenerate case of multi-user. The runtime doesn't care who's looking — it sends render trees and streams to "a client."

- Two developers connect to the same runtime. Both see the same structured state with independent viewports, scroll positions, and selections (client-owned widget state). This isn't screen sharing — it's a shared semantic workspace.
- A human and an AI agent share a session. The human's client renders a GUI. The agent's client parses typed data. Same state, different consumption.
- Live handoff is just reconnection. You disconnect, your colleague connects, the runtime sends a snapshot. Zero ceremony.
- Async effect review: a developer queues effects and disconnects. A teammate connects, sees the pending effects in `runtime/effects`, approves or rejects. Code review at the system-call level.
- Audit trails are free. Every effect is a data record with identity, timestamp, and status.

## Infrastructure

Every DevOps tool today has its own dashboard, API, and query language. Pond replaces that fragmentation with one contract: typed streams in, effects out.

- A deployment pipeline is a session of composable apps. Each stage publishes typed streams (compilation progress, test results, rollout percentage). Any client composes them.
- Incident response: connect to the runtime on the affected host. See CPU, processes, containers, logs as typed streams. Issue effects (restart, scale, rollback) through the same protocol. The incident timeline is the literal sequence of effects issued and stream states observed.
- Fleet management: one client, many runtimes. Each server manages local state. The client composes streams across all of them.
- Live infrastructure state, not plan-then-apply. Drift appears in the stream the moment it happens. Apply is an effect with its progress visible as a stream.

## Universal app platform

Write an app once, render it on any client — native, web, TUI, mobile, tablet. Effects are portable across machines. The runtime handles local vs remote transparently.

- One program, many surfaces. A render tree renders as native AppKit on macOS, native HTML on web, native cells in a TUI. The app author wrote one thing.
- Remote is the primary case. An iPad connecting to a headless dev server gets the same fidelity as a desktop client.
- Composition replaces integration glue. If two tools publish typed streams, a client can compose them. No middleware, no adapters, no webhooks.
- The introspection model eliminates tool categories. The runtime exposes its own state as streams — monitoring, debugging, and administration are just Pond apps subscribing to runtime streams.

## The far edges

Every Pond session is a serializable artifact. Effects are replayable. Streams are observable. Render trees are inspectable.

- **Time-travel debugging.** Replay a session and watch every state change. Every effect, every stream update, every render tree mutation.
- **Testable programs.** Assert which effects an app emits for a given state without performing them.
- **Archaeological computing.** A session log from 2026 replays identically in 2076. The protocol is the contract, not the OS or hardware.
- **Living documents.** A research paper where every figure is a live render tree driven by the actual analysis code. Reviewers subscribe to the data streams and tweak parameters.
- **Accessibility by construction.** Clients get structured render trees, not pixels. Screen readers and alternative input devices get first-class structured data — not an afterthought.
- **AI interpretability by construction.** An agent's perceptions (stream subscriptions), intentions (effects), and expressions (render trees) form a complete, typed, replayable record. Not interpretability research — interpretability as a property of the protocol.

## The one-line version

Pond externalizes computational intent into a protocol. What a program wants to show, what work it wants done, what data it produces — all first-class, portable, subscribable, composable, and replayable.
