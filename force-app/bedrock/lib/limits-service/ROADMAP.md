# LimitsService — Roadmap

Shared limit-awareness infrastructure. This folder has no implemented code yet —
it is future, proposed work. Cross-cutting roadmap principles and feature
sequencing live in the repo root `ROADMAP.md`.

`LimitsService` is deliberately *shared* infrastructure beneath the separate
work pools (`Async`, `Event`, `Scheduler`): sharing a mechanism is not
collapsing the pools. It is a standalone injectable service — **not** an `Async`
inner class — since it serves all of them.

These are intended designs, not finalized public APIs. Ask before locking
names, schemas, or behavior that does not exist yet.

## LimitsService + limits-safe operations

Status: **blocked by Scheduler MVP1** (`../scheduler/ROADMAP.md` — the resume
monitor).

`LimitsService` is the shared limit-awareness layer that decides whether it is
safe to enqueue Queueables, publish events, or start pending work.

**Behavior:**

- Exposes current Queueable, SOQL, CPU, heap, and DML usage as ratios against
  org/transaction limits in a testable way.
- `isSafe()` returns false when any tracked resource exceeds
  `Limits_Threshold_Pct__c` (from `Async.SettingsService`, see
  `../async/ROADMAP.md`).
- Consulted by `JobService.canEnqueue()` and the finalizer before enqueuing new
  work. If Queueable limits are exhausted, all framework job pools pause pending
  work rather than burning it or failing noisily.
- **Pause/resume:** when unsafe, pending work moves to a `Paused` status instead
  of being dropped. The Scheduler MVP1 monitor (~every 15 min) re-checks
  `isSafe()`; if safe, `Paused` items flip back to `Pending` and re-enqueue. If
  still exhausted, it waits for the next run.
- Keep it human/developer-first: clear state, explainable behavior, maintainable
  recovery over opaque automation.

## Consumers

- `Async` (`../async/ROADMAP.md`) — the finalizer and `JobService.canEnqueue()`
  consult `isSafe()` before enqueuing.
- Multithreading (`../thread-service/ROADMAP.md`) — a thread starts only when a
  slot is available AND `LimitsService.isSafe()`. LimitsService is the
  cross-pool org-health backstop.
- `Event` (`../event/ROADMAP.md`) — consulted before publishing events or
  starting event work.
