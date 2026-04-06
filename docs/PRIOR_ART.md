# Prior Art

What exists, what Pond takes from each, and what's different.

---

## 1. Arcan / A12 / Cat9

A display server with a structured IPC protocol (SHMIF over shared memory), a network protocol (A12) aiming to replace SSH+VNC+RDP, and a shell replacement (Cat9) that models jobs as trackable objects. One-person project by Bjorn Stahl, ~13 years.

A12 is the most relevant piece. It's a custom protocol that carries everything — video frames, audio, input events, binary blobs, clipboard — over a single encrypted connection. Five packet types (control, event, video, audio, binary), multiplexed channels per segment, ChaCha8+BLAKE3 encryption, X25519 key exchange, TOFU trust model. Segments (Arcan's equivalent of windows) are independently addressable and independently compressed. A12 also has directory servers for discovery and application distribution, and supports live migration of segments between display servers.

**What Pond takes:**
- The idea that a display protocol should carry structure, not just pixels
- Capability-mediated sandboxing: programs request access, the runtime grants or denies
- Cat9's job-as-object model: a running process is a first-class thing with identity, state, and streams, not a line of text
- A12's TOFU identity model: cryptographic identity detached from hostname, trust established on first connection
- A12's TPACK text encoding: structured cell data (color + attributes + glyph) instead of pixel bitmaps for text content
- A12's directory servers: federated discovery and rendezvous without DNS dependency
- A12's unified transport: one protocol for everything, no side-band channels

**What's different:**
- Arcan replaces the OS display stack (compositor, window manager, display server). Pond is a network protocol with its own identity, capability, and discovery model. You connect to a runtime, not a shell.
- A12 carries pixel frames and audio samples — it's optimized for spatial content. Pond carries semantic widgets, typed data, and declared effects — it's optimized for structured content. A12 needs video codecs (H.264, delta-PNG). Pond needs structural diffing and columnar compression.
- A12 segments are visual surfaces. Pond streams are typed data channels. A12 migrates a window. Pond migrates application state.
- Arcan is C+Lua. Pond apps can be written in any language that speaks the wire protocol.
- Arcan is a complete desktop environment. Pond is a protocol that multiple clients can implement.

**Link:** https://arcan-fe.com

---

## 2. A2UI (Google, 2025)

A protocol for agents to present UI to humans. Declarative JSON component trees rendered natively per platform. The closest overlap with Pond's render trees.

**What Pond takes:**
- The validation that declarative component trees over a wire are the right abstraction for remote UI

**What's different:**
- A2UI is agent-to-human only. It has no model for human-to-agent interaction, agent-to-agent composition, or bidirectional data flow.
- No typed streams. An A2UI component is a snapshot, not a live binding to a data source.
- No effects. The agent produces UI; it doesn't declare intent that the runtime fulfills.
- No session persistence or reconnection. No shared sessions.

**Link:** https://github.com/nichochar/a2ui

---

## 3. AG-UI + MCP

The current agent protocol stack. MCP handles tool calling (request-response), AG-UI handles event streaming (server-sent events for partial outputs), and MCP Apps embed HTML-in-iframe for UI.

**What Pond takes:**
- The observation that agents need both tool invocation and streaming output
- The lesson that tool calling alone (MCP without AG-UI) is insufficient for real-time agent UX

**What's different:**
- MCP has no render trees. MCP Apps use HTML blobs in iframes, not structured widgets.
- Streams are not composable primitives. You can't subscribe to an MCP tool's output from another tool, or compose two agents' streams into one view.
- No session persistence. If the connection drops, state is lost.
- The stack requires stitching three protocols together (MCP for tools, AG-UI for streaming, MCP Apps for UI). Pond is one protocol.

**Link:** https://modelcontextprotocol.io, https://docs.ag-ui.com

---

## 4. Elm Architecture

Client-side web framework where the app is a pure function: `Model -> (View, Cmd)`. Serializable effects (`Cmd`), declarative render trees (the `view` function), managed side effects (the Elm runtime fulfills commands). The closest conceptual ancestor to Pond's app model.

**What Pond takes:**
- Apps declare what they want, not how to do it
- Effects as plain data: serializable, inspectable, testable
- The runtime, not the app, owns side effects
- Render trees as the return value of application logic

**What's different:**
- Elm is a client-side web framework. It compiles to JavaScript and runs in a browser.
- No wire protocol. The Elm runtime and the view are in the same process.
- No streams as a first-class concept. Elm has subscriptions, but they're local to one program, not shared between programs.
- No remote sessions, reconnection, or multi-client observation.

**Link:** https://elm-lang.org

---

## 5. Phoenix LiveView

Server-rendered UI for the web. The server holds application state, renders HTML, and sends structured diffs over a WebSocket. The client patches the DOM. Session persistence survives disconnects (briefly).

**What Pond takes:**
- The proof that server-is-truth with structured diffs is viable for interactive UI at real-world latencies
- The idea that reconnection sends current state, not a replay log

**What's different:**
- Web-only. The wire carries HTML diffs. Clients must be browsers (or something that understands the DOM).
- No typed streams. Data flows through template rendering, not as independently subscribable channels.
- No effects as a protocol concept. Server-side code calls functions directly.
- No multi-program composition. A LiveView is one application, not a workspace of composable programs.

**Link:** https://hexdocs.pm/phoenix_live_view

---

## 6. Mosh

A remote terminal that maintains server-side terminal state and uses its own State Synchronization Protocol (SSP) over UDP. Both sides maintain screen state snapshots; the server sends idempotent diffs between numbered states. Can skip intermediate frames — always converges to latest. On reconnect, the server sends a screen snapshot instead of replaying history. Local echo predicts the effect of keystrokes and renders immediately, correcting when server state arrives. Roaming works by tracking the source IP of the highest-sequence authentic packet.

**What Pond takes:**
- The insight that server-is-truth plus snapshot-first reconnect is the correct architecture for remote terminals
- The observation that local echo (predicting what the server will show) makes latency tolerable
- The proof that UDP-based state synchronization (idempotent diffs, skip frames, converge) works for interactive remoting
- Roaming by tracking the highest-sequence authenticated packet, not by IP address

**What's different:**
- Still a cell grid. Mosh transmits terminal state (characters, colors, cursor position), not semantic meaning. A table rendered in Mosh is still a grid of characters.
- No structure. Mosh can't distinguish a menu from a paragraph from a progress bar.
- No composition, streams, effects, or multi-program awareness. It's a better pipe for the same bytes.
- Mosh built its own UDP protocol before QUIC existed. QUIC provides the same benefits (connection migration, loss tolerance) with TLS 1.3 encryption, multiplexed streams, and congestion control — without reimplementing them.

**Link:** https://mosh.org

---

## 7. TermKit (2011)

A terminal replacement that added rich, typed output (MIME-typed data in pipes, rendered as images, tables, and interactive widgets). The cautionary tale.

**What Pond takes:**
- The lesson of what killed it. TermKit required every Unix tool to be rewritten to emit MIME-typed output. Adoption was zero because nothing worked on day one.
- Pond's answer: server-side VTE normalization means `ls`, `vim`, `htop` work immediately through the `terminal` widget. Native Pond apps are the goal; legacy compatibility is the bridge.

**What's different:**
- TermKit tried to make the terminal richer. Pond replaces the terminal with a structured protocol and contains legacy terminal support in one optional widget.
- TermKit was client-side. There was no runtime, no session persistence, no remote-first architecture.

**Link:** https://github.com/unconed/TermKit

---

## 8. Nushell / PowerShell

Shells where pipelines carry structured data (tables, records, lists) instead of text. `ls` returns a table of objects. `where size > 10mb` filters on a typed column, not a regex.

**What Pond takes:**
- The proof that structured data in pipelines is dramatically better than text parsing
- The vocabulary: tables, records, and typed columns as pipeline primitives

**What's different:**
- No render trees. Nushell formats structured data into text for display. The rendering is a lossy final step, not a declared UI.
- No effects. Commands execute directly; there's no declared-intent layer.
- No session persistence or reconnection. Shell state lives in memory and dies with the process.
- No remote protocol. Nushell is a local shell. Using it remotely means SSH + a terminal emulator, which puts you back to byte streams.
- No multi-program composition through streams. Pipelines are linear and ephemeral.

**Links:** https://www.nushell.sh, https://learn.microsoft.com/en-us/powershell

---

## 9. Accessibility APIs (AT-SPI, UI Automation, NSAccessibility)

Every major platform already exposes a structured UI tree for screen readers. Buttons have labels, tables have rows, trees have children. Agents can use these today, right now, with every existing application.

This is the strongest practical challenge to Pond: why build a new protocol when structured UI trees already exist and every app already implements them?

**What Pond takes:**
- The validation that structured UI trees are the right abstraction. Accessibility APIs prove that semantic widgets work for non-visual consumers.

**What's different:**
- Read-only scraping, not a protocol apps implement. Accessibility trees describe what's on screen after the fact. They don't carry data types, stream bindings, or declared effects.
- No data layer. An accessibility tree tells you "this table has a row labeled '42% CPU'." It doesn't give you the number 42 as a typed value you can compute on.
- No effects. You can click a button through an accessibility API, but the API doesn't tell you what the button will do. There's no declared intent.
- No composition. You can't subscribe to one app's accessibility tree from another app.
- Brittle. Accessibility trees are an afterthought in most apps. Labels are missing, roles are wrong, state is inconsistent. The structure exists but the quality is unreliable.

**Links:** https://www.freedesktop.org/wiki/Accessibility, https://learn.microsoft.com/en-us/windows/win32/winauto/ui-automation-specification

---

## 10. Jupyter

A protocol for interactive computing. A kernel executes code and returns structured output (MIME-typed: text, HTML, images, JSON). Notebooks compose cells into documents. The kernel protocol is language-agnostic.

**What Pond takes:**
- Structured, typed output from programs as a protocol-level concept
- Language-agnostic kernel protocol: the idea that the wire protocol shouldn't dictate the implementation language

**What's different:**
- No render trees. Jupyter outputs are MIME blobs (HTML, PNG, SVG). The client displays them but can't interact with their internal structure.
- No effects. Kernels execute code directly with full system access. There's no capability model or declared intent.
- No live composition. Cells are sequential, not concurrent. You can't subscribe to one kernel's output stream from another kernel.
- No session persistence in the Pond sense. Notebooks persist as documents, but kernel state (variables, connections) is lost on restart.
- Document-oriented, not workspace-oriented. A Jupyter session is one notebook, not a composable set of programs sharing a runtime.

**Link:** https://jupyter.org

---

## Summary matrix

Which of Pond's five properties does each system have?

| System | Render trees | Typed streams | Serializable effects | Session persistence | Dual-use (human + agent) |
|---|---|---|---|---|---|
| **Arcan / A12 / Cat9** | Pixel frames (TPACK for text) | Structured (SHMIF) | Partial (capability model) | Yes (A12, with migration) | No |
| **A2UI** | Yes | No | No | No | Agent-to-human only |
| **AG-UI + MCP** | HTML blobs | Event streams (not composable) | Tool calls (not serializable data) | No | Agent-focused |
| **Elm** | Yes | No (local subscriptions) | Yes | No | No |
| **Phoenix LiveView** | HTML diffs | No | No | Partial (brief reconnect) | No |
| **Mosh** | Cell grid | No | No | Yes (snapshot) | No |
| **TermKit** | Partial (MIME) | No | No | No | No |
| **Nushell / PowerShell** | No | Partial (pipeline-only) | No | No | No |
| **Accessibility APIs** | Yes (read-only) | No | No | No | Partial (read-only) |
| **Jupyter** | MIME blobs | No | No | Partial (document) | No |
| **Pond** | Yes | Yes | Yes | Yes | Yes |

No existing system combines all five. The closest in spirit is Arcan, which has structured protocols and session persistence but operates at the pixel level and replaces the display stack. The closest in shape is the Elm Architecture, which has render trees and serializable effects but is a client-side framework, not a wire protocol.

Pond's bet is that these five properties compose into something qualitatively different: a single protocol where programs declare UI, exchange typed data, and request work, and the same primitives serve human rendering, agent interaction, composition, persistence, and replay.
