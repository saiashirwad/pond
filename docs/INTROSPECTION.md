# Introspection

The runtime's own internal state is exposed as ordinary streams, through the same protocol apps use.

No separate admin API. No `pondctl`. No monitoring stack. The system observes itself through its own primitives.

## The principle

Ingalls, on Smalltalk:

> "Every component accessible to the user should be able to present itself in a meaningful way for observation and manipulation."

Applied to Pond: if the protocol gives you typed streams, schema discovery, and commands, then the runtime should use those same mechanisms to describe itself. The runtime is the first program in its own system.

## What becomes streams

The runtime already tracks this state internally. Making it streams means any Pond program can observe it.

**Sessions:**
```
runtime/sessions  ->  [{ id, name, created_at, program_count, client_count }]
runtime/connections  ->  [{ client_id, connected_since, latency_ms, bytes_sent, bytes_recv }]
```

**Programs:**
```
runtime/programs  ->  [{ id, name, pid, state, cpu, mem, streams_published, uptime }]
runtime/effects  ->  [{ id, program_id, type, status, issued_at, completed_at }]
```

**Stream catalog (the catalog is itself a stream):**
```
runtime/streams  ->  [{ address, schema, mode, version, update_rate_hz, subscriber_count }]
```

**Wire stats:**
```
runtime/wire  ->  { send_buffer_bytes, recv_buffer_bytes, msgs_per_sec, priority_queue_depths }
```

These are state-mode streams with schemas, versioning, and the same update semantics as any app's output.

## What becomes commands

The runtime declares commands just like any program:

```
runtime/commands:
  - kill_program { program_id, signal }
  - create_session { name }
  - destroy_session { session_id }
  - detach_client { client_id }
```

Same `cmd.invoke` / `cmd.result` messages. A session manager program invokes commands against `runtime` the same way it would against any other program.

## What this enables

### Programs with zero data-collection logic

A process monitor subscribes to `runtime/programs` and declares a table view. The program is just a view:

```json
{
  "type": "table",
  "id": "procs",
  "bind": "runtime/programs",
  "props": {
    "columns": [
      { "key": "name", "label": "Name", "flex": 1 },
      { "key": "cpu", "label": "CPU%", "width": 6 },
      { "key": "mem", "label": "Mem", "width": 10 }
    ],
    "sortable": true
  }
}
```

No `/proc` parsing. No `ps aux`. No state management. The runtime already has the data. The program contributes nothing except a render tree.

### Session management as an ordinary program

`tmux list-sessions` becomes a program that binds a list widget to `runtime/sessions`. `tmux kill-session` becomes a `cmd.invoke` against the runtime. There's no separate management interface.

### Debugging as subscription

"Why is this widget showing stale data?" Subscribe to `runtime/streams`, find the stream, check its `update_rate_hz` and `version`. "Why is my connection laggy?" Subscribe to `runtime/wire`, check `priority_queue_depths`. The answers are already in the system. You just need a view.

### Self-observation

A Pond program that monitors the runtime is itself a program managed by the runtime, which means it appears in `runtime/programs`, which means it can observe itself.

This is the Smalltalk mirror: the system browser is written in Smalltalk, browsable through itself. The inspector is an object, inspectable through itself. There's no meta-level.

## The design constraint

If runtime internals are streams, they need schemas. They need versioning. They need to follow the same update semantics as app output.

This is a good constraint. It forces the runtime's internal model to be well-structured. The act of exposing forces clarity.

## Where it doesn't fully hold

**Bootstrap.** The `hello`/`hello_ok` handshake must complete before any streams exist. The bootstrap sequence is necessarily special. Smalltalk has the same problem: the image must be loaded before objects exist.

**Performance.** If the runtime exposes high-frequency internal state, it needs to respect the same throttling as any other stream. Monitoring widgets declare their update cadence; the runtime only computes stats at the rate someone is actually watching.

**Security.** For a single-user SSH session, full visibility is fine (you can already `ps aux`). Multi-user scenarios would need per-session visibility scoping.

## The payoff

This eliminates an entire API surface. There's no CLI tool that speaks a different protocol. No REST API. No admin socket. One protocol, and the runtime speaks it about itself.

It also means the "Pond Inspector" (an inspect overlay on any widget, showing its bound stream, current value, update rate, owning program) is just a Pond program. It subscribes to `runtime/streams` and `runtime/programs`. It renders with the same widgets everything else uses. It's not special.
