# Network

[`TRANSPORT.md`](TRANSPORT.md) specifies how bytes move between a client and a runtime: SSH, Unix sockets, QUIC. This document specifies the network layer above transport — how runtimes and clients identify each other, what they're authorized to do, how they discover each other, and how multiple runtimes compose into a single workspace.

## Why Pond needs its own network model

SSH says: "here's a pipe to a shell. Good luck."

Pond says: "here's a structured contract — here's what you can see, do, and interact with."

SSH is a transport for bytes. Pond carries meaning — typed streams, declared effects, structured render trees. Every message has a schema. Every action is auditable. Every capability is explicit. The network model should reflect this:

- **Security is structural.** There is no shell to accidentally expose. Clients get capabilities, not user accounts.
- **Composition is natural.** Streams from different runtimes share the same schema. One view, many sources.
- **Migration is possible.** State is data, not opaque process memory. Apps can move between runtimes.
- **Disconnection is handled.** Effects are serializable intent. They can queue, transfer, and replay.

## Identity

Runtimes and clients have cryptographic identities: ed25519 keypairs generated on first run.

A runtime's identity is its public key. It doesn't change when the IP changes, when the host reboots, or when the port shifts. Trust is TOFU (Trust On First Use) — first connection, verify the fingerprint. After that, the identity is tracked regardless of network address.

```
$ pond connect devbox
New runtime. Fingerprint: sha256:a4f3...b7e2
Trust this runtime? [y/N]
```

After trust is established:
- The runtime can change IPs, ports, hostnames — the client reconnects by identity, not by address
- MITM requires compromising the stored key, not just DNS
- No certificate authority, no PKI

This is the same model SSH uses for host keys, detached from hostname resolution. Clients have identities too. A runtime can pre-authorize specific client keys, or use TOFU for interactive approval.

## Capabilities, not shell access

SSH authenticates a user and grants a Unix shell. Once in, you can do anything the Unix user can do. No granularity.

Pond authenticates clients and grants **capabilities** — cryptographic tokens specifying exactly what the bearer can do:

```json
{
  "identity": "ed25519:client-pubkey",
  "grants": [
    { "streams": ["docker/containers", "docker/logs/*"], "mode": "observe" },
    { "effects": ["docker.restart", "docker.stop"], "scope": "container:api-*" },
    { "apps": ["monitor"], "mode": "interact" }
  ],
  "expires": "2026-04-07T00:00:00Z",
  "issuer": "ed25519:runtime-pubkey",
  "signature": "..."
}
```

A monitoring dashboard gets read-only stream tokens. An agent gets scoped effect tokens. A colleague gets full session access. The runtime rejects unauthorized messages structurally — not through Unix permissions, through the protocol.

### Issuance

Capability tokens are signed by the runtime's identity key. They can be:

- **Bootstrapped via SSH.** The SSH session proves the user's identity. The runtime issues a Pond capability token. After that, SSH is never needed again.
- **Issued by a directory server.** A central authority grants tokens based on its own policy.
- **Delegated.** A client with sufficient capabilities can mint narrower tokens for others. You can't escalate — only restrict.
- **Revoked.** The runtime maintains a revocation list. Revoked tokens are rejected immediately.

### First connection (no SSH)

```
Client                              Runtime
  |                                      |
  |  1. QUIC connect (TLS 1.3)          |
  |  ──────────────────────────────────> |
  |                                      |
  |  2. Present client public key        |
  |  ──────────────────────────────────> |
  |                                      |  3. Check trust store
  |                                      |     (TOFU or pre-authorized)
  |                                      |
  |  4. Challenge-response               |
  |  <──────────────────────────────────>|
  |                                      |
  |  5. Capability token                 |
  |  <───────────────────────────────────|
  |                                      |
  |  6. hello / hello_ok                 |
  |  <──────────────────────────────────>|
  |                                      |
```

No SSH involved. The client connects directly to the runtime's QUIC port. Identity verification and capability issuance happen in the Pond protocol itself.

When SSH is available, the first connection can use an SSH session as the trust anchor instead — the SSH session proves who you are, the runtime issues a capability token, and subsequent connections use that token directly. This is backward-compatible with the v2 transport's SSH bootstrap in [`TRANSPORT.md`](TRANSPORT.md).

### What this solves

The README's open question — "What can an app do by default?" — is answered at the protocol level. Apps declare capabilities they need. The runtime grants or refuses. Clients can only invoke effects and observe streams within their capability scope. No ambient authority.

## Discovery

### Local: mDNS

Runtimes announce themselves on the local network:

```
_pond._udp.local.
  devbox._pond._udp.local. → 192.168.1.47:4200
    txt: id=sha256:a4f3...b7e2
    txt: version=1
    txt: name=devbox
```

`pond discover` lists all runtimes on the local network. No SSH config, no `/etc/hosts`, no manual IP entry.

### Named connections

`pond connect devbox`, not `ssh user@192.168.1.47`.

Resolution order:
1. **Local trust store** — previously connected runtimes, keyed by name and identity
2. **mDNS** — local network scan
3. **Directory server** — if configured (see below)
4. **DNS** — SRV/TXT records at `_pond._tcp.devbox.example.com`

Names are human-friendly aliases for cryptographic identities. The name can change; the identity is what the client verifies.

### Peer exchange

A runtime that knows about other runtimes can share that knowledge:

```
runtime/peers → [{ name, identity, address, last_seen, streams_published }]
```

Connect to one runtime, discover its neighbors. Sharing is scoped by the client's capabilities — you only see peers you're authorized to know about.

### Directory servers

A directory server is a Pond runtime dedicated to rendezvous and discovery. It maintains a registry of runtimes, their identities, published streams, and access policies.

Runtimes register with a directory server on startup:

```
Runtime → Directory:  register { name, identity, address, streams: [...] }
Directory → Runtime:  registered { directory_id, ttl }
```

Clients query the directory:

```
Client → Directory:  resolve { name: "devbox" }
Directory → Client:  { identity, address, streams, capabilities_required }
```

Directory servers can link to each other. A query that can't be resolved locally is forwarded to linked directories. This forms a discovery mesh — not DNS, not a centralized registry, but a federated network of Pond runtimes that know about each other.

A directory server is not a special component. It's a regular Pond runtime running directory apps. You monitor it with Pond. It publishes streams about its own registry state.

## Cross-runtime streams

### The problem

The vision says: "one client composing streams from many runtimes." The transport layer is point-to-point. Fleet management means N separate sessions.

### Stream addressing

Streams get full addresses when crossing runtime boundaries:

- **Local:** `docker/containers` — the containers stream on the connected runtime
- **Remote:** `prod-1/docker/containers` — the containers stream on the runtime named prod-1

Within a single runtime, addresses are unchanged. The full form is only needed when a client is connected to multiple runtimes.

### Multi-runtime composition

A client holds QUIC connections to multiple runtimes simultaneously. Render trees can bind to streams from any connected runtime:

```json
{
  "type": "table",
  "id": "fleet-containers",
  "bind": [
    "prod-1/docker/containers",
    "prod-2/docker/containers",
    "prod-3/docker/containers"
  ],
  "merge": "concat",
  "columns": [
    { "key": "_runtime", "label": "Host" },
    { "key": "name", "label": "Container" },
    { "key": "status", "label": "Status" }
  ]
}
```

One view, three runtimes. Each connection has independent QUIC flow control. Backpressure on prod-3 doesn't affect prod-1.

The `_runtime` field is injected by the client — it identifies which runtime a row came from. The program doesn't know or care how many runtimes are behind the binding.

### Effects are always local

Effects are fulfilled by the runtime that receives them. A client issues effects to specific runtimes:

```json
{ "target": "prod-1", "effect": "docker.restart", "args": { "container": "api" } }
```

There is no "broadcast effect." Multi-runtime effects are explicit — the client (or a relay) issues individual effects to individual runtimes. This is deliberate: effects have consequences, and those consequences should be traceable to a specific target.

## Relay nodes

### The problem

50 runtimes from your laptop means 50 QUIC connections. This doesn't scale — and 50 independent data streams all converging on one client defeats backpressure.

### What a relay is

A relay is a Pond runtime that connects to other runtimes and re-publishes their streams:

```
              ┌─────────┐
Client ←────→ │  Relay  │ ←────→ Runtime 1
              │         │ ←────→ Runtime 2
              │         │ ←────→ Runtime 3
              └─────────┘
```

The client connects to one relay. The relay maintains connections to the fleet. Backend streams are available under their full addresses.

A relay is not a special component. It's a regular Pond runtime running relay apps that subscribe to upstream streams and re-publish them. Same protocol, same primitives. You monitor the relay with Pond.

### What a relay adds

- **Aggregation.** One client connection instead of N. All backend streams available in one session.
- **Caching.** Stream snapshot caching for instant client reconnection, even if a backend runtime is briefly unreachable.
- **Policy.** Rate limiting, access control, stream filtering — enforced before data reaches the client.
- **Fan-out.** Client issues "restart api on all prod nodes." Relay fans to individual runtimes, collects results, returns aggregate status.
- **Resilience.** Backend disconnects? Relay serves cached state and queues effects for delivery when the backend returns.

### Relay topology

Relays can connect to relays. Regional relays aggregate local runtimes. A global relay aggregates regional relays. The topology is a DAG — a runtime can be reachable through multiple paths.

```
                    ┌──────────────┐
         Client ───→│ Global Relay │
                    └──────┬───────┘
                     ┌─────┴──────┐
              ┌──────┴──┐    ┌────┴─────┐
              │ US Relay │    │ EU Relay │
              └──┬───┬──┘    └──┬───┬───┘
                 │   │          │   │
               us-1 us-2     eu-1 eu-2
```

## State migration

Pond apps describe UI and request work. They don't hold sockets, file handles, or process state directly — the runtime holds those through effects. This means an app's state is serializable: render tree, stream snapshots, pending effects, bound stream addresses.

```
$ pond migrate myapp --from devbox --to laptop
```

The sequence:
1. Source runtime serializes the app's state
2. State transfers to the destination runtime over a direct QUIC connection (or via relay)
3. Destination runtime creates the app from the serialized state
4. Stream bindings either rebind to local resources or become cross-runtime references
5. Source runtime stops the app

Use cases:
- Move a dev environment to your laptop before a flight
- Evacuate apps before host maintenance
- Load-balance across runtimes

### Limitation

Migration is for Pond-native apps only. PTY programs have opaque process state — they can't be serialized or moved. Migration works precisely because Pond apps declare intent through effects rather than holding resources directly.

## Offline effects

Effects are serializable data. The protocol exploits this during disconnection:

1. Client goes offline (tunnel, flight, network blip)
2. User keeps interacting — effects queue locally with timestamps
3. On reconnect, client sends queued effects
4. Runtime evaluates each against current state:
   - **Valid** — state hasn't changed incompatibly → execute
   - **Stale** — conditions changed → reject with reason and current state
   - **Conflicting** — another client issued a contradicting effect → reject with conflict info

This works because effects are declared intent, not direct operations. "Restart container api" can be evaluated for validity regardless of when it was issued.

Queued effects are tagged `{ queued_at, queued_offline: true }` so the runtime and audit systems can distinguish them from real-time effects.

### What the client shows

While offline:
- Render trees freeze at last known state
- Effects show as "queued" in the UI (the client owns this — it's widget-local state)
- On reconnect, queued effects resolve to "executed" or "rejected with reason"
- Stream data resumes from current state (snapshot-first reconnection, same as any other reconnect)

## Content-aware encoding

The protocol knows what it's carrying. Different data types get different encoding:

| Data type | Strategy | Why |
|---|---|---|
| Render tree diffs | Structural (add/remove/update node) | Trees change shape slowly; <1KB typical |
| Table/list streams | Columnar delta (only changed columns) | Status column changes; name column doesn't |
| Log streams | Line-oriented, ZSTD with stream dictionary | Logs repeat patterns obsessively |
| Terminal cells | TPACK-style (color + attrs + glyph) | Structured text, not pixels (from A12) |
| Metrics streams | Delta-of-delta (Gorilla-style) | 43%, 44%, 43% → near-zero bytes |
| Binary blobs | ZSTD, block size matched to blob size | Generic compression |

Encoding is negotiated per-stream based on declared type. Apps don't choose encoding. The runtime and client handle it transparently. The wire format in [`TRANSPORT.md`](TRANSPORT.md) carries the encoded payloads; this layer determines how payloads are produced.

This matters because Pond carries structured data, not pixels. A12 must optimize for video frame transport. Pond's heaviest payload is a render tree snapshot (~200KB for a full 20-app session). The right compression strategy is structural and columnar, not spatial.

## Progressive bootstrap

SSH bootstrap requires uploading a 5-10MB binary before anything works. The native protocol offers better options:

### Runtime as daemon

The runtime is a long-running service, not uploaded per-session. Install once (package manager, container, manual copy). The client connects directly to the runtime's QUIC port. No upload, no SSH, no shell.

```
$ pond-runtime serve --port 4200    # on the server, once
$ pond connect devbox               # from the client, always
```

Auto-update: the runtime checks a configured source (directory server, URL) for new versions and restarts itself. The client doesn't need to carry binaries.

### Thin SSH bootstrap (backward-compatible)

For servers where you have SSH access but haven't installed the runtime:

1. Client SSH's in, runs `pond-runtime --version`
2. If missing or outdated, uploads the binary via SFTP (same as v1)
3. Runtime starts, opens a QUIC port, hands back connection parameters
4. Client disconnects SSH, connects via QUIC
5. Runtime issues a capability token — SSH is never needed again for this runtime

This is the v2 bootstrap from [`TRANSPORT.md`](TRANSPORT.md), extended with persistent capability tokens.

### Registry distribution

Runtimes can be published to a directory server. When a client connects to a host that doesn't have a runtime:

1. Client SSH's in, determines runtime is missing
2. Client tells the remote host to fetch the runtime from a directory server
3. Remote host downloads directly (no client upload)
4. Runtime starts and issues capability tokens

This avoids uploading over a slow client connection. The server fetches from wherever is fastest.

## Relationship to transport

| Layer | Concern | Document |
|---|---|---|
| Transport | How bytes move (SSH, Unix socket, QUIC) | [`TRANSPORT.md`](TRANSPORT.md) |
| Network | How endpoints find, trust, authorize, and compose with each other | This document |
| Application | Message types, render trees, streams, effects | [`README.md`](../README.md) |

Transport is the pipe. Network is the plumbing.
