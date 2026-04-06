# Transport

Pond's application protocol is transport-agnostic. Nine message types, length-prefixed frames, MessagePack or JSON payloads. The framing layer reads and writes an ordered, reliable byte stream. It does not know or care whether that stream is an SSH channel, a Unix socket, or a QUIC stream.

This document specifies how the protocol maps to concrete transports.

## The transport abstraction

The framing layer needs exactly two things from a transport:

1. **Ordered byte delivery.** Bytes arrive in the order they were sent.
2. **Reliable delivery.** No bytes are silently dropped.

That's it. The framing layer calls `read(buf)` and `write(buf)` on an abstract stream. TCP, SSH channels, Unix sockets, and QUIC streams all satisfy this. UDP does not.

The framing layer does not assume:
- Encryption (SSH provides it; Unix sockets don't need it)
- Multiplexing (SSH has channels; Unix sockets don't; QUIC has streams)
- Authentication (handled below the framing layer, before it runs)
- Compression (SSH can compress; the protocol doesn't depend on it)

## Wire format

Every message on the wire:

```
[4 bytes: payload length, big-endian u32] [payload]
```

Maximum frame size: 16 MB (2^24). Any frame exceeding this is a protocol error. The payload is a MessagePack (or JSON, see README open questions) encoded message with a `type` field that determines its schema.

The framing layer reads a length prefix, allocates a buffer, reads exactly that many bytes, decodes. On the write side: encode, prepend length, write. This is the entire contract between the application protocol and the transport.

## v1: SSH transport

SSH is the v1 transport. It handles authentication, encryption, firewall traversal, and host key verification. Pond doesn't reimplement any of these.

### Connection sequence

```
Client                              Remote Host
  |                                      |
  |  1. SSH connect (OpenSSH client)     |
  |  ──────────────────────────────────> |
  |     auth (key, password, agent)      |
  |                                      |
  |  2. exec: "pond-runtime serve"       |
  |  ──────────────────────────────────> |
  |                                      |  3. Runtime starts, writes to stdout
  |                                      |
  |  4. hello  ─────────────────────────>|
  |                                      |
  |  5. hello_ok  <──────────────────────|
  |                                      |
  |  6. Framed messages (stdin/stdout)   |
  |  <──────────────────────────────────>|
  |                                      |
```

Step 2 uses SSH's `exec` channel, not an interactive shell. This is critical — it avoids the shell banner problem entirely.

### stdin/stdout mapping

The SSH channel's stdin and stdout become the bidirectional byte stream the framing layer operates on.

- **Client to runtime:** client writes framed messages to the SSH channel's stdin.
- **Runtime to client:** runtime writes framed messages to its stdout, which the SSH channel delivers to the client.
- **stderr:** reserved for runtime diagnostic output (startup errors, panics). Never carries protocol messages. The client logs it but does not parse it as framed data.

The runtime must not write anything to stdout before it is ready to speak the protocol. No version banners, no "starting up..." messages. The first bytes on stdout are either the runtime's `hello_ok` response (if the client speaks first) or the length prefix of the first protocol frame.

### Shell banner problem

Interactive SSH sessions source `.bashrc`, `.profile`, and `/etc/motd`. Their output lands on stdout and corrupts framing. Pond avoids this entirely:

**The client uses SSH `exec`, not an interactive shell.** `ssh host pond-runtime serve` runs the command directly. No shell sourcing, no TTY allocation, no banner. The SSH channel carries only the runtime's stdout.

If `pond-runtime` is not in `$PATH` on the remote host, the client uses the absolute path from the bootstrap step (see below).

### Runtime bootstrap (auto-upload)

The remote host may not have `pond-runtime` installed. The client handles this transparently.

```
Client                              Remote Host
  |                                      |
  |  1. exec: "pond-runtime --version"   |
  |  ──────────────────────────────────> |
  |                                      |
  |  [exit 0, version compatible]        |
  |  <───────────────────────────────────|
  |  -> skip to "exec: pond-runtime      |
  |     serve"                           |
  |                                      |
  |  [exit nonzero or version too old]   |
  |  <───────────────────────────────────|
  |                                      |
  |  2. sftp: upload pond-runtime to     |
  |     ~/.pond/bin/pond-runtime         |
  |  ──────────────────────────────────> |
  |                                      |
  |  3. exec: "chmod +x                  |
  |     ~/.pond/bin/pond-runtime"        |
  |  ──────────────────────────────────> |
  |                                      |
  |  4. exec: "~/.pond/bin/pond-runtime  |
  |     serve"                           |
  |  ──────────────────────────────────> |
  |                                      |
```

The runtime is a single static binary (5-10 MB, no dependencies). Upload uses SFTP over the existing SSH connection. On a slow uplink this blocks — acceptable for first connect. Subsequent connects skip the upload if the version matches.

The client carries binaries for common architectures (linux/amd64, linux/arm64, darwin/amd64, darwin/arm64). It detects the remote arch with `uname -m` before uploading.

### Reconnection over SSH

SSH connections die. When the client reconnects:

1. New SSH connection, new `exec: pond-runtime serve`.
2. The runtime was already running (daemonized on first connect, or managed by systemd/launchd). The new `pond-runtime serve` invocation detects the existing runtime and connects to it internally (via the Unix socket described in v1.1).
3. The client sends `hello` with its `session_id` from the previous connection.
4. The runtime sends full state snapshots for all apps, focused app first. Sequence numbers continue; they don't reset.

If the runtime process itself died (host reboot, OOM kill), reconnection starts a fresh session. The client knows this because `hello_ok` returns a new `session_id`.

### Daemonization

On first connect, the runtime forks into the background. The foreground process (the one SSH `exec`'d) becomes a thin relay between the SSH channel and the daemon's Unix socket. When SSH disconnects, the relay dies, but the daemon keeps running — apps survive.

The runtime ignores SIGHUP. It writes its PID to `~/.pond/runtime.pid`.

### Priority send queues over SSH

SSH gives one ordered byte stream. No transport-level priority. The runtime implements priority at the application level:

**Three queues, drained in order:**

1. **Control** — `hello_ok`, `error`, `cmd.result`, acknowledgments. Always drained first.
2. **Render** — `render` messages (UI updates). Drained after control.
3. **Data** — `stream.data` messages (bulk output from programs). Drained last.

The write loop:
```
loop:
  while control_queue has messages:
    write(control_queue.pop())
  while render_queue has messages:
    write(render_queue.pop())
  if data_queue has messages:
    write(data_queue.pop())  // one at a time, then re-check control/render
```

Data messages yield after each write so that a `find /` dumping results doesn't starve a keystroke acknowledgment or a UI redraw. Per-program output is capped at ~64 KB buffered; excess is dropped with a `stream.truncated` notification.

On the read side (client to runtime), no priority is needed — input volume is negligible compared to output.

## v1.1: Unix socket transport

When the runtime is on localhost, SSH is overhead. Unix sockets skip network setup, encryption, and the SSH handshake.

### When to use it

- Local development: the runtime runs on the same machine as the client.
- Browser clients: a WebSocket proxy bridges the browser to the Unix socket.
- Inter-process: Pond programs that need to talk to the runtime directly.
- Testing: no SSH setup needed.

### Socket path

```
~/.pond/runtime.sock
```

The directory `~/.pond/` is created with mode `0700` (owner-only). The socket file inherits directory permissions — only the owning user can connect.

If `$XDG_RUNTIME_DIR` is set, prefer `$XDG_RUNTIME_DIR/pond/runtime.sock` (tmpfs, cleaned on logout).

### Connection sequence

```
Client                              Runtime
  |                                    |
  |  1. connect(~/.pond/runtime.sock)  |
  |  ─────────────────────────────────>|
  |                                    |
  |  2. hello  ───────────────────────>|
  |                                    |
  |  3. hello_ok  <────────────────────|
  |                                    |
  |  4. Framed messages                |
  |  <────────────────────────────────>|
  |                                    |
```

No authentication step. The filesystem permission model is the auth: if you can open the socket, you're the user who owns the runtime. This matches the SSH trust model — once you've SSH'd in, you are that user.

The framing layer operates identically to SSH. Same length-prefixed frames, same message types. The transport is a different file descriptor, nothing else.

### WebSocket proxy for browsers

Browsers cannot open Unix sockets. A thin proxy bridges WebSocket to the Unix socket:

```
Browser                  Proxy                    Runtime
  |                        |                         |
  |  1. WebSocket connect  |                         |
  |  ─────────────────────>|                         |
  |                        |  2. connect(runtime.sock)|
  |                        |  ───────────────────────>|
  |                        |                         |
  |  3. Binary WS frames   |  4. Byte stream         |
  |  <────────────────────>|  <─────────────────────>|
  |                        |                         |
```

The proxy is a separate process (`pond-proxy`), not part of the runtime. It does one thing: accept WebSocket connections, open a Unix socket to the runtime, and shuttle bytes. No message parsing, no buffering logic, no state. Raw bidirectional byte relay.

The proxy binds to `localhost:8765` by default. It serves only loopback — browser clients on the same machine. Remote browser access is a non-goal for v1.1; it comes with QUIC in v2.

WebSocket binary frames map directly to the framing layer's byte stream. The proxy concatenates incoming WS frames into the stream and splits outgoing bytes at frame boundaries (or arbitrary boundaries — the framing layer handles reassembly).

### Priority queues over Unix sockets

Same application-level priority queues as SSH. The transport is still a single ordered byte stream. The runtime's write loop is identical.

## v2: QUIC transport

QUIC solves the problems SSH can't: multiplexed streams with independent flow control, connection migration, and 0-RTT reconnection. This is the mosh pattern — SSH authenticates, QUIC carries data.

### Why QUIC

- **Independent stream flow control.** A fast producer on one stream doesn't block renders on another. SSH's single byte stream means one slow reader blocks everything.
- **Connection migration.** Laptop moves from Wi-Fi to cellular — the QUIC connection survives. SSH dies and requires full reconnection.
- **0-RTT reconnection.** After the first connection, subsequent connects resume in zero round trips. SSH requires a full handshake every time.
- **Head-of-line blocking.** TCP (and therefore SSH) enforces ordering across the entire connection. One lost packet stalls all data. QUIC's streams are independently ordered — a lost packet on the data stream doesn't stall the control stream.
- **WebTransport.** Browsers can speak QUIC natively via WebTransport, eliminating the WebSocket proxy.

### SSH bootstrap sequence

SSH is still the authentication layer. The client never implements its own auth.

```
Client                              Remote Host
  |                                      |
  |  1. SSH connect + auth               |
  |  ──────────────────────────────────> |
  |                                      |
  |  2. exec: "pond-runtime              |
  |     quic-setup"                      |
  |  ──────────────────────────────────> |
  |                                      |  3. Runtime generates:
  |                                      |     - session token (32 bytes, random)
  |                                      |     - QUIC port (ephemeral)
  |                                      |     - TLS cert fingerprint
  |                                      |
  |  4. { "token": "...",               |
  |       "port": 42017,                 |
  |       "fingerprint": "sha256:..." }  |
  |  <───────────────────────────────────|
  |                                      |
  |  5. SSH connection closes            |
  |                                      |
  |  6. QUIC connect to host:42017       |
  |     (TLS, verify fingerprint)        |
  |  ──────────────────────────────────> |
  |                                      |
  |  7. Send token on stream 0           |
  |  ──────────────────────────────────> |
  |                                      |  8. Runtime verifies token
  |                                      |
  |  9. hello / hello_ok on stream 0     |
  |  <──────────────────────────────────>|
  |                                      |
  | 10. Multiplexed streams              |
  |  <──────────────────────────────────>|
  |                                      |
```

The SSH connection is short-lived — seconds. It exists only to authenticate the user and exchange the QUIC session parameters. The token is single-use and expires after 30 seconds if not claimed.

The runtime uses a self-signed TLS certificate for QUIC. The client trusts it by verifying the fingerprint received over the SSH channel (which is itself authenticated). No CA needed.

### Stream mapping

QUIC provides multiplexed, independently flow-controlled streams. Pond maps its logical channels to QUIC streams:

**Stream 0: Control.** Bidirectional. Carries `hello`/`hello_ok`, `error`, `cmd.invoke`/`cmd.result`. Always open.

**Stream 1: Render.** Runtime-to-client, unidirectional. Carries all `render` messages. Separate from control so that a large render tree update doesn't block a `cmd.result`.

**Per-program data streams.** Each program's `stream.data` output gets its own QUIC stream, opened by the runtime when the client subscribes. Stream ID is communicated in the `hello_ok` or `stream.subscribe_ok` response.

This means:
- A `find /` producing output at full speed fills its own QUIC stream. QUIC's per-stream flow control applies backpressure to that stream alone.
- Render updates flow on stream 1, unaffected by data backpressure.
- Control messages on stream 0 are never blocked by anything.
- The client can prioritize reading from stream 0, then stream 1, then data streams — but the transport enforces independence regardless.

When a program exits or the client unsubscribes, the runtime closes the program's QUIC stream with a FIN. Clean, no tombstone messages needed.

### Priority with QUIC

Priority is now transport-level, not application-level. QUIC allows stream prioritization:

| QUIC stream | Pond channel | Priority |
|-------------|-------------|----------|
| Stream 0    | Control     | Highest  |
| Stream 1    | Render      | High     |
| Per-program | Data        | Normal   |

The runtime sets QUIC stream priorities, and the QUIC implementation handles scheduling. The application-level priority queue from v1 is no longer needed — the transport does it natively.

### 0-RTT reconnection

After the first QUIC connection, the client caches the TLS session ticket. On reconnect:

```
Client                              Runtime
  |                                      |
  |  1. QUIC 0-RTT connect              |
  |     (cached session ticket +         |
  |      session token in early data)    |
  |  ──────────────────────────────────> |
  |                                      |  2. Verify token + ticket
  |                                      |
  |  3. hello (with session_id)          |
  |  ──────────────────────────────────> |
  |                                      |
  |  4. hello_ok + state snapshots       |
  |  <───────────────────────────────────|
  |                                      |
```

No SSH involved. No TLS handshake round trip. The session token (long-lived, rotated periodically) authenticates the client. Combined with QUIC's 0-RTT, this gets the client back to a working session in a single flight.

The session token has a bounded lifetime (hours, configurable). When it expires, the client falls back to a fresh SSH bootstrap to obtain a new one.

### Connection migration

Laptop closes its lid, reconnects on a different network. IP address changes. QUIC uses connection IDs, not the 4-tuple (src IP, src port, dst IP, dst port), to identify connections. The client sends packets from the new address with the same connection ID. The runtime accepts them after path validation.

From Pond's perspective: nothing happens. No reconnect, no state resend, no sequence number reset. The transport handled it.

### WebTransport for browsers

QUIC enables WebTransport, a browser API for multiplexed bidirectional streams over HTTP/3.

```
Browser                              Runtime (QUIC + HTTP/3)
  |                                      |
  |  1. WebTransport connect             |
  |     (https://host:port/.well-known/  |
  |      pond)                           |
  |  ──────────────────────────────────> |
  |                                      |
  |  2. Authenticate (session token      |
  |     obtained via prior auth flow)    |
  |  ──────────────────────────────────> |
  |                                      |
  |  3. Multiple bidirectional streams   |
  |  <──────────────────────────────────>|
  |                                      |
```

The browser client gets the same multiplexed streams as the native QUIC client. No WebSocket proxy. No application-level priority queues. The browser authenticates using a session token obtained through a separate flow (OAuth redirect, SSH-established cookie, etc. — details TBD for v2).

## Why NOT alternatives

### Why not a custom UDP protocol

QUIC already solves reliable delivery, congestion control, flow control, multiplexing, encryption, and connection migration. Reimplementing any of these is years of work and will be worse. Mosh built its own UDP protocol before QUIC existed; we don't need to.

A custom UDP protocol also means a custom security story. QUIC uses TLS 1.3. Audited, understood, trusted. A custom protocol gets audited by nobody.

### Why not replace SSH for authentication (in v1 and v2)

SSH key management is a solved, deployed problem. Every server has sshd. Every developer has SSH keys. Key agents, hardware tokens, certificates, ProxyJump, bastion hosts — all work. For v1 and v2, SSH exists, it works, and it handles auth.

[`NETWORK.md`](NETWORK.md) describes a path beyond SSH: ed25519 identity keypairs, TOFU trust, and capability tokens that make SSH optional after the first connection. The SSH bootstrap remains available as a backward-compatible onramp — but it's no longer the only way in.

### Why not WebSocket everywhere

WebSockets run over TCP. TCP has head-of-line blocking. WebSockets are a single ordered stream — no multiplexing without application-level framing on top. They exist because browsers can't do better; native clients can.

For v1.1's local browser access, WebSocket over the Unix socket proxy is fine — there's no network latency or packet loss, so TCP's weaknesses don't matter. For remote browser access in v2, WebTransport over QUIC is strictly better.

### Why not HTTP/2

HTTP/2 multiplexes streams over a single TCP connection. It solves the application-level head-of-line blocking (streams are independent at the HTTP layer) but not the transport-level problem (one lost TCP packet blocks all streams). QUIC fixes this at the transport layer.

HTTP/2 also requires a full HTTP request/response model that doesn't map naturally to Pond's bidirectional message streams.

## Summary

| Version | Transport | Auth | Multiplexing | Priority | Browser support |
|---------|-----------|------|-------------|----------|----------------|
| v1 | SSH stdin/stdout | SSH keys | None (single stream) | Application-level queues | None |
| v1.1 | Unix socket | Filesystem permissions | None (single stream) | Application-level queues | WebSocket proxy (local only) |
| v2 | QUIC | SSH bootstrap + session token | Native QUIC streams | Transport-level stream priority | WebTransport |

The application protocol is identical across all three. The framing layer reads and writes bytes. Everything below that — authentication, encryption, multiplexing, priority enforcement — is the transport's problem.

For the network layer above transport — identity, capabilities, discovery, cross-runtime composition, relay nodes, state migration, and content-aware encoding — see [`NETWORK.md`](NETWORK.md).
