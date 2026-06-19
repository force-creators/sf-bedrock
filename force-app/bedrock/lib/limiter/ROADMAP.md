# Limiter — Roadmap

`Limiter` is implemented in this folder. The current contract is the Apex source
and `AGENTS.md`; this roadmap tracks remaining integration ideas.

## Current Baseline

- `Limiter.getLimits()` exposes tracked transaction and org/platform limits.
- `Limiter.getLimit(...)` and `Limiter.isSafe(...)` are mockable.
- Known limit names are available through `Limiter.types`.
- Thread-based work consults `Limiter` before unsafe Queueable starts.
- EventRelay publish work consults Platform Event limits before publishing.
- Paused thread recovery is owned by `Thread.recover()`.

## Remaining Work

- **Threshold ownership:** keep thresholds owned by consuming frameworks unless a
  shared setting proves simpler.
- **Additional tracked limits:** add enum names only when framework code needs a
  stable known limit. Subscriber code can still use Salesforce-provided
  `OrgLimits` keys with `getLimit(String)`.
- **Operator messaging:** keep pause reasons specific enough that an admin can
  tell which quota blocked work.
- **Console/docs integration:** document how Async, EventRelay, and Thread use
  `Limiter`, and expose limit-driven pauses in admin views if those views are
  added.

## Non-Goals For Now

- No Limiter-owned work queue.
- No Limiter-specific resume job separate from Thread recovery unless a
  non-threaded consumer needs one.
- No broad settings surface before concrete consumers need it.
