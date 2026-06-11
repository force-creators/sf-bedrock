# PlatformCache and PlatformCacheMock — Agent Guide

Component guide for the `PlatformCache` library. Global conventions (Apex
style, testing rules, the Salesforce MCP deploy/validate workflow, architecture
layers) live in the repo root `AGENTS.md`. Inspect the code in this folder
before depending on exact method behavior.

## What it is

`PlatformCache` is the cache dependency injection layer for Salesforce Platform
Cache. It provides small `Org` and `Session` adapters so production code can
use platform cache directly while tests can substitute a mock partition.

## Current shape

- `PlatformCache` is an abstract base exposing `get`, `put`, and `remove`.
- `PlatformCache.Partition` is the concrete cache adapter that talks to
  `Cache.Org` or `Cache.Session` based on scope.
- `PlatformCache.Org` and `PlatformCache.Session` are thin virtual wrappers
  over `PlatformCache.Partition` so feature-specific cache classes can extend
  them with a fixed partition name.
- `PlatformCache.PartitionRegistry` resolves org and session partitions and can
  return a registered mock partition for either scope.
- `PlatformCache.setMock(...)` currently registers a partition mock by
  partition name for tests.
- `PlatformCacheMock` extends `PlatformCache.Partition`, stores values in
  memory, and records `gets`, `puts`, and `removes` for assertions.

## Testing notes

- Tests should usually verify org and session behaviors in distinct units such
  as `testOrg_get` and `testSession_put`, rather than combining the entire
  happy path in one method.
- When mocking, remember that the current registry is partition-name based, so
  direct org/session adapters and subclasses that share a partition name will
  use the same registered mock.

## Composition

The planned `Selector.Cached` variant (see `../selector/ROADMAP.md`) builds on
`PlatformCache`.
