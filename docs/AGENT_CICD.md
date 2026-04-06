# CI/CD Agent Architecture

An agent on Pond is just another program: it subscribes to streams, emits effects, and shares the session with humans. This document specifies what that looks like for CI/CD.

## 1. What the agent sees

Four stream families. All are state-mode streams with schemas.

**Build stream** (`ci/build/{run_id}`):
```
{ run_id, commit, branch, step, status, started_at, duration_ms, image, cache_hit }
```
Updates per-step (clone, deps, compile, package). Typically 4-8 updates per build.

**Test stream** (`ci/tests/{run_id}`):
```
{ suite, name, status, duration_ms, attempt, flaky, error, stdout_tail }
```
One entry per test. Also an aggregate sibling (`ci/tests/{run_id}/summary`):
```
{ passed, failed, skipped, flaky_count, wall_time_ms }
```

**Deploy stream** (`ci/deploy/{env}/{run_id}`):
```
{ stage, status, target, replicas_ready, health_check, rollout_pct, error }
```
Stages: `image_push`, `canary`, `rolling`, `complete`. Health checks are sub-entries with `{ endpoint, latency_p99, error_rate, status_code_dist }`.

**Log stream** (`ci/logs/{run_id}/{step}`): Structured entries, not raw text.
```
{ ts, level, source, message, structured }
```
`source` is one of `compiler`, `runtime`, `infra`, `test_runner`. The CI app that wraps the build tool classifies errors at emission time. The agent never parses raw output — the Pond app publishing the stream does the parsing. This is Pond's model: structure at the source, not at the consumer.

## 2. What the agent can do

Every action is an effect — serializable, interceptable, logged.

| Effect | Payload |
|---|---|
| `ci.retry` | `{ run_id, step?, reason }` |
| `ci.skip_test` | `{ run_id, suite, name, reason, ttl }` |
| `ci.rollback` | `{ env, to_version, reason }` |
| `ci.deploy.pause` | `{ env, run_id }` |
| `ci.deploy.resume` | `{ env, run_id }` |
| `ci.scale` | `{ env, resource, replicas, reason, ttl }` |
| `ci.pr.open` | `{ repo, branch, title, body, diff }` |
| `ci.notify` | `{ channel, severity, message, context }` |
| `ci.cancel` | `{ run_id, reason }` |
| `ci.approve_gate` | `{ run_id, gate_name }` |

Every effect carries a `reason` field. This isn't decoration — it's the agent's reasoning trace, stored in the effect log.

## 3. Cross-stream reasoning

The agent subscribes to multiple streams and correlates them. The logic is straightforward pattern matching on stream state:

**Build passes, tests fail.** Agent reads `ci/logs/{run_id}/test` with `source: "compiler"` or `source: "runtime"`. If failures are in changed files (diff available from the build stream's `commit`), it's a code issue. Effect: `ci.notify` to the author, optionally `ci.pr.open` with a fix if the error is mechanical (missing import, type mismatch).

**Tests flaky.** Agent checks `attempt > 1` and `flaky: true` across recent runs. If a test has failed-then-passed 3+ times in 7 days, it's flaky. Effect: `ci.skip_test` with a TTL (auto-re-enables after 48h), plus `ci.notify` to the owning team. Different from a hard failure: no retry, no block.

**Deploy health checks fail.** Agent correlates `ci/deploy/{env}/{run_id}` health checks with `ci/metrics/{env}/pods` (pod-level metrics stream). If error rate spike correlates with a specific pod, effect: targeted `ci.scale` (replace that pod) rather than full `ci.rollback`. If the error is across all pods, it's the new code — `ci.rollback`.

**Latency spike during canary.** Agent compares `health_check.latency_p99` between canary and stable pods. If canary p99 exceeds stable by >2x, effect: `ci.deploy.pause` + `ci.notify`. Human decides whether to proceed or rollback.

The correlation is possible because all streams share a session and are typed. The agent doesn't scrape dashboards — it reads structured data through `subscribe`.

## 4. Human review

The effect log (`runtime/effects`) is the audit trail. A human connects to the same Pond session. What they see:

**Timeline view.** Each effect is a row: timestamp, type, status (pending/approved/executed/rejected), the agent's `reason`, and a link to the stream snapshot the agent observed when it decided. This isn't reconstructed — Pond's serializable sessions mean the stream state at decision time is literally replayable.

**Decision context.** Selecting an effect shows: "Agent saw test X fail 3/5 runs. Streams observed: `ci/tests/run-447`, `ci/tests/run-445`, `ci/tests/run-441`. Emitted: `ci.skip_test { name: 'test_oauth_refresh', ttl: '48h' }`." The human sees inputs and outputs together, not just the action.

**Pending approvals.** Effects requiring confirmation (see below) appear as a queue. The human approves, rejects, or modifies parameters before execution. This is a standard Pond render tree — a list widget bound to `runtime/effects` filtered by `status: "pending"`.

## 5. Safety guardrails

Three mechanisms, all structural (enforced by the runtime, not by the agent's good behavior).

**Capability scoping.** The agent's capability token lists exactly which effects it can emit and which streams it can observe. A monitoring agent gets `observe: ci/*` but no effect grants. A deploy agent gets `effects: [ci.rollback, ci.deploy.*]` scoped to `env: staging`. Production rollback requires a different token. This is Pond's existing capability model from `NETWORK.md` — not a CI-specific addition.

**Effect approval tiers.** The runtime intercepts effects before execution. Three tiers:

| Tier | Examples | Behavior |
|---|---|---|
| Auto-approved | `ci.retry`, `ci.notify`, `ci.skip_test` (with TTL) | Execute immediately. Low blast radius. |
| Human-confirm | `ci.rollback`, `ci.deploy.pause`, `ci.pr.open` | Queued as pending. Human approves/rejects. Timeout: 15 min, then auto-reject. |
| Forbidden | `ci.deploy.resume` to prod after auto-rollback | Rejected structurally. Cannot be emitted regardless of capability. |

Tiers are configurable per environment. `ci.rollback` on staging might be auto-approved; on production it requires confirmation.

**Blast radius limits.** Encoded in the capability token's `scope` field:
- `ci.scale` capped at `replicas: max 10` — the agent can't scale to 1000
- `ci.rollback` scoped to `env: staging` — can't touch production
- `ci.skip_test` requires `ttl` — can't permanently suppress a test
- Rate limiting: max 3 rollbacks per hour per environment

**Dry-run mode.** The agent emits effects normally. The runtime logs them with `status: "dry_run"` and does not execute. The human reviews the full decision log, then switches to live mode. This is a capability token flag: `{ "dry_run": true }`. The agent's code doesn't change between dry-run and live — the runtime enforces it.
