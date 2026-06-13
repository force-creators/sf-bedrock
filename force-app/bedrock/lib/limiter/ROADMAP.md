# Limiter — Roadmap

Shared limit-awareness infrastructure. The core `Limiter.isSafe()` gate is
implemented; pause/resume integration remains future work. Cross-cutting roadmap
principles and feature sequencing live in the repo root `ROADMAP.md`.

`Limiter` is deliberately *shared* infrastructure beneath the separate
work pools (`Async`, `Event`, `Scheduler`): sharing a mechanism is not
collapsing the pools. It is a standalone injectable service — **not** an `Async`
inner class — since it serves all of them.

These are intended designs, not finalized public APIs. Ask before locking
names, schemas, or behavior that does not exist yet.

## Limiter + limits-safe operations

Status: **core gate implemented; pause/resume blocked by Scheduler MVP1**
(`../scheduler/ROADMAP.md` — the resume monitor).

`Limiter` is the shared limit-awareness layer that decides whether it is
safe to enqueue Queueables, publish events, or start pending work.

**Behavior:**

- Exposes current transaction limits and Salesforce org/platform limits as
  ratios in a testable way, including Queueable enqueue usage, SOQL, CPU, heap,
  DML, daily async, platform event, streaming, API, storage, and other
  Salesforce-provided org quotas.
- `getLimits()` exposes all tracked limits, and `getLimit(name)` reads a specific
  limit.
- `isSafe(name)` and `isSafe(name, thresholdPercent)` check one tracked limit.
  Consuming frameworks own threshold settings and pass them when needed.
- Planned consumers consult `isSafe(name, thresholdPercent)` before enqueuing new
  work. If Queueable limits are exhausted, all framework job pools should pause
  pending work rather than burning it or failing noisily.
- **Pause/resume:** when unsafe, pending work moves to a `Paused` status instead
  of being dropped. The Scheduler MVP1 monitor (~every 15 min) re-checks
  `isSafe()`; if safe, `Paused` items flip back to `Pending` and re-enqueue. If
  still exhausted, it waits for the next run.
- Keep it human/developer-first: clear state, explainable behavior, maintainable
  recovery over opaque automation.

## Consumers

- `Async` (`../async/ROADMAP.md`) — future integration should make the finalizer
  and `JobService.canEnqueue()` consult `isSafe()` before enqueuing.
- Multithreading (`../thread-service/ROADMAP.md`) — a thread starts only when a
  slot is available AND `Limiter.isSafe()`. Limiter is the
  cross-pool org-health backstop.
- `Event` (`../event/ROADMAP.md`) — consulted before publishing events or
  starting event work.
