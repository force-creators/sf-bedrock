# Limiter — Agent Guide

Component guide for the `Limiter` framework. Global conventions (Apex
style, testing rules, the Salesforce MCP deploy/validate workflow, architecture
layers) live in the repo root `AGENTS.md`. Remaining integration ideas live in
`./ROADMAP.md`.

## What it is

`Limiter` is shared, standalone limit-awareness infrastructure. It is not
an `Async` inner class. It exists so Async, Scheduler, Event, ThreadService, or
subscriber code can depend on one testable org-health gate before starting more
work.

## Current shape

- `Limiter.getLimits()` returns all tracked transaction and org/platform
  limits keyed by limit name.
- `Limiter.getLimit(name)` returns one tracked limit by name, or `null`
  when the name is not present.
- `Limiter.isSafe(name)` checks one tracked limit against the default
  90 percent threshold.
- `Limiter.isSafe(name, thresholdPercent)` checks one tracked limit against
  a caller-provided threshold. It returns false when the name is missing.
- `Limiter.types` is a nested enum for known limits such as
  `QUEUEABLE_JOBS`, `SOQL_QUERIES`, `DAILY_ASYNC_APEX_EXECUTIONS`, and
  `DAILY_STANDARD_VOLUME_PLATFORM_EVENTS`. `getLimit` and `isSafe` both have
  enum overloads so framework code does not need magic strings for known limits.
- `Limiter.LimitUsage` exposes `name`, `used`, `allowed`, `remaining`, and
  `ratio` for a single limit.
- `Limiter.Service` is the injectable implementation surface.
- `LimiterMock` can seed named limit usage for unit tests.

## Notes

- Consumers should call `Limiter.isSafe(name, thresholdPercent)` from their own
  enqueue/start points.
- Platform limit names are Salesforce-provided `OrgLimits` keys. Use
  `Limiter.getLimit('<OrgLimitName>')` when a consumer needs a specific
  transaction or platform quota that is not represented in `types`.
- The planned `Async_Settings__c.Limits_Threshold_Pct__c` integration is not
  implemented yet. Threshold values are expected to be owned by consuming
  frameworks and passed to `isSafe(name, thresholdPercent)`.
- Thread-based pause/resume behavior is owned by the shared `Thread` service.
