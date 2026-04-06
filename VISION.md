# Vision

Pond is a structured interface protocol — a universal contract for how programs describe what they want to show, what data they have, and what work they want done.

## Composable infrastructure

Every infrastructure tool today has its own dashboard, API, and query language. Prometheus speaks PromQL, kubectl speaks YAML, Terraform speaks HCL, your CI system has its own web UI. To correlate "the deploy happened at 2:03, CPU spiked at 2:04, error rate climbed at 2:05" you switch between tabs and eyeball timestamps.

Pond replaces this with one contract: typed streams in, effects out.

- Each tool becomes an app publishing typed streams. CPU metrics, container status, deploy progress, error rates — all structured, all subscribable, all composable in one view.
- A dashboard that shows CPU alongside deploy progress alongside error rate isn't a product you buy — it's a layout subscribing to three streams.
- A program that subscribes to `deployer/events` AND `logger/errors` and auto-rolls-back when error rate spikes is 10 lines, not a custom integration between your deploy system and your error tracker.
- Incident response is one session: connect to the runtime on the affected host, see everything as typed streams, issue effects (restart, scale, rollback) through the same protocol. The incident timeline is the literal log of effects issued and stream states observed.
- Fleet management: one client composing streams from many runtimes. Each server manages local state. Filter, correlate, and act across machines through stream composition.

Pond doesn't replace Kubernetes or Docker. It replaces the experience layer around them — the dashboards, CLIs, monitoring tools, and integration glue. If every component published typed streams and accepted effects through one protocol, you wouldn't need half the ecosystem.

### Docker as a first-class citizen

Docker already has a structured API on a Unix socket. A Pond app wraps it and publishes typed streams:

```
docker-pond/containers  → [{ id, name, image, status, cpu, mem, ports }]
docker-pond/images      → [{ id, tag, size, created }]
docker-pond/logs/api-1  → live log stream
```

Effects map to Docker API calls: start, stop, restart, pull, rm. Container logs become typed log-mode streams. One Pond session where Docker containers are just another set of streams alongside your own apps, your build output, your monitoring data.

The deeper version: each container runs its own Pond runtime. The host-level stream tells you container-1 is running. Container-1's own runtime tells you what's happening inside it. Compose them in one view.

## Write once, render anywhere

You build a process monitor. Today, you choose: CLI, TUI, web dashboard, native app, mobile. Each is a separate frontend. Or you pick one and everyone else adapts.

In Pond, you write one program that declares a render tree and publishes streams. A native macOS client renders it with AppKit. A web client renders it as HTML. A TUI client renders it as a character grid. A phone renders it as a native list with touch scrolling. The program didn't change. It doesn't know which client is rendering it.

- Remote is the primary case. An iPad connecting to a headless dev server gets the same structured UI as a desktop client. Not a degraded mobile web view — the same render tree, rendered natively.
- Composition replaces integration glue. Your file browser, editor, and build system are all Pond apps on the same runtime. The editor subscribes to the build system's diagnostics stream and shows inline errors. Nobody wrote an integration — the streams already exist.
- The runtime exposes its own state as streams. Monitoring, debugging, and administration are just apps subscribing to runtime streams. No separate admin tooling.

The cost of building tools today is dominated by the frontend, not the logic. Pond makes the frontend a commodity — the protocol carries the structure, clients render it natively.

## Effects and streams as agent primitives

Agents don't need better GUIs. They need better primitives for interacting with the world.

- Serializable effects mean every agent action is logged, inspectable, and replayable by construction
- Runtime interception means effects can be refused before they happen — the precondition for agent safety that most systems make structurally difficult
- Typed stream composition gives multi-step workflows real structure instead of stdout parsing
- Shared sessions let a human and an agent occupy the same runtime — the human sees a GUI, the agent sees typed data

An agent is just another program. No special mode needed.

## A network, not a connection

SSH gives you a pipe to one machine. Pond gives you a network of runtimes.

- **Discovery:** runtimes announce themselves. `pond discover` shows what's on your network. No SSH config, no IPs to remember.
- **Identity:** runtimes and clients have cryptographic identities that survive IP changes, reboots, and network moves. Trust is established once, verified forever.
- **Capabilities:** clients get scoped tokens — observe these streams, issue these effects. Not "here's a shell, do anything." A monitoring dashboard sees metrics. An agent sees what it needs. A colleague sees what you've shared.
- **Cross-runtime composition:** one client, many runtimes. A dashboard that shows containers from prod-1 alongside errors from prod-2 alongside build status from your dev server is just stream bindings.
- **Relay nodes:** at fleet scale, a relay aggregates streams from many runtimes into one connection. The relay is itself a Pond runtime — you monitor it with Pond.
- **State migration:** move a running app from your VPS to your laptop. The app's state is serializable data, not opaque process memory.
- **Offline effects:** effects queue during disconnection and execute on reconnect. Because effects are declared intent, not direct operations, the runtime can evaluate them for validity against current state.

The protocol carries meaning, not bytes. The network model should too. See [`docs/NETWORK.md`](docs/NETWORK.md).

## Shared semantic workspaces

The runtime doesn't care who's looking. Render trees and streams go to "a client" — one or five.

- Two people connect to the same runtime with independent viewports and selections. Not screen sharing — a shared workspace with structured state.
- A human and an AI agent share a session. Same state, different consumption.
- Live handoff is reconnection. Async review is inspecting queued effects. Audit trails are subscribing to `runtime/effects`.

## Serializable sessions

Every Pond session is an artifact. Effects are replayable. Streams are observable. Render trees are inspectable.

- Time-travel debugging — replay a session and watch every state change
- Testable programs — assert which effects an app emits without performing them
- Accessibility by construction — clients get structured render trees, not pixels
- AI interpretability by construction — an agent's perceptions, intentions, and expressions are a typed, replayable record
