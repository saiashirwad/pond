# Supervision

Programs crash. The question is what else should happen when they do.

Today: a program dies, its subscribers get `stream.stale`, and recovery is the user's problem. Supervision makes recovery structural.

## The model (from Erlang)

A **group** is a set of programs with a declared restart strategy. The runtime manages the lifecycle. Programs don't know they're supervised.

Three strategies:

**`one_for_one`** — restart only the program that died. Use when programs are independent.

**`one_for_all`** — kill and restart all programs in the group. Use when programs share assumptions and a partial restart would leave the group inconsistent.

**`rest_for_one`** — kill and restart everything started *after* the crashed program. Use when programs have startup-order dependencies: B depends on A, C depends on B. If A dies, B and C are stale.

Per-program restart types:

- `permanent` — always restart
- `transient` — restart only on abnormal exit (crash, signal), not on clean exit
- `temporary` — never restart

Restart intensity: "if this program crashes more than N times in M seconds, stop trying." The group itself fails, which the user (or a parent group) handles.

## Why it works in Pond

Supervision requires isolation — restarting one thing must be safe for its siblings. Pond has this:

- Programs are OS processes with separate memory
- Communication is only through streams, mediated by the runtime
- Stream state lives in the runtime, not in programs
- A restarted program gets a fresh pipe and re-declares its streams

Killing and restarting a program doesn't corrupt anything else. The new instance subscribes to the streams it needs and starts publishing. The runtime reconnects the wiring.

## Example

A dev workspace:

```
file-watcher  → publishes "fs/changes"
build-runner  → subscribes to "fs/changes", publishes "build/diagnostics"
editor        → binds to "build/diagnostics" for inline errors
terminal      → runs bash, independent
```

```json
{
  "groups": [
    {
      "strategy": "rest_for_one",
      "max_restarts": 5,
      "max_seconds": 60,
      "programs": [
        { "command": "pond-fswatcher", "args": ["."], "restart": "permanent" },
        { "command": "pond-builder", "restart": "permanent" },
        { "command": "pond-editor", "restart": "permanent" }
      ]
    },
    {
      "strategy": "one_for_one",
      "programs": [
        { "command": "bash", "restart": "temporary" }
      ]
    }
  ]
}
```

File watcher crashes. The runtime kills build-runner and editor (rest_for_one), then restarts all three in order. The editor's bound stream gets a fresh snapshot from the restarted build runner. The terminal is in a separate group and unaffected.

## Open question

Should a restarted program keep its old `program_id`? If yes, existing render tree bindings survive transparently. If no, the client sees a new program and must rebind. Preserving the id is simpler for clients but means the runtime must remap stream ownership — the Smalltalk `become:` problem.
