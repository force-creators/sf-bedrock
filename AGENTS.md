# sf-bedrock Agent Guide

sf-bedrock is a Salesforce base-org/domain/service/selector layer for stable,
testable Apex automation. The goal is enterprise-safe code that stays readable
for the humans who own it.

The owner does not trust AI code blindly. Work in small, inspectable steps,
explain tradeoffs, and keep implementation easy for a Salesforce engineer to
review.

## Source Of Truth

- Implemented Bedrock library code lives in `force-app/bedrock/lib`.
- Each implemented library has a local guide at
  `force-app/bedrock/lib/<component>/AGENTS.md`; read only the relevant guide.
- Roadmaps record intended direction, not implemented contracts. Names, schema,
  metadata, and behavior that do not exist in `force-app/bedrock/lib` need an
  explicit plan before implementation.
- Ignore prototype or scratch Apex outside `force-app/bedrock/lib` unless the
  task explicitly brings it into scope.
- Preserve local user work. Do not revert unrelated dirty or untracked files.

## Working Rules

- Use a plan-first posture for meaningful framework work. Tiny fixes under about
  10 lines may be implemented directly.
- Prefer the smallest useful change set. Avoid broad refactors, speculative
  abstractions, and unrelated cleanup.
- Existing public Apex APIs may evolve carefully, but call out compatibility
  impact before changing public names or signatures.
- Read narrowly. Prefer targeted files, line ranges, and symbol searches over
  broad dumps.
- Keep commands quiet. Prefer scoped `rg`, targeted test runs, and short command
  output.
- Prefer Apex and JavaScript work. Do not create new Salesforce metadata files
  unless the task explicitly requires it; if new schema is needed, tell the user
  what to scaffold.

## Salesforce Validation

Use `sf-bedrock` explicitly as the target org alias.

Prefer Salesforce DX MCP tools over raw CLI when an equivalent exists:

- Deploy metadata: `mcp__salesforce_dx.deploy_metadata`
- Retrieve metadata: `mcp__salesforce_dx.retrieve_metadata`
- Run Apex tests: `mcp__salesforce_dx.run_apex_test`
- Run SOQL queries: `mcp__salesforce_dx.run_soql_query`
- Resolve an unclear org alias: `mcp__salesforce_dx.get_username`
- Resume a long-running org operation:
  `mcp__salesforce_dx.resume_tool_operation`

Validation rules:

- Do not run Salesforce Code Analyzer for this repo.
- After changing Apex or Salesforce metadata, deploy the touched source before
  considering the edit complete.
- If tests changed, deploy the touched production classes, mocks, helpers, and
  tests, then run the smallest relevant Apex test set.
- Treat deploy errors as compiler truth. Fix task-related compile, metadata, or
  test failures autonomously and rerun the narrow validation.
- If org access fails because of keychain, auth, or sandbox permissions, retry
  with the approved escalation flow for a CLI fallback before reporting blocked.
- For Salesforce MCP tools or CLI fallbacks, wait up to 10 seconds. If an
  operation is still running, stop polling and report the exact tool or command
  the user can run directly.

## Architecture

Keep layer boundaries clear:

- Schema: `SObject` definitions, metadata, settings, and configuration.
- Domain: triggers, record lifecycle automation, and domain logic.
- Selector: query logic and reusable data access.
- UI: Lightning, Flexipages, Visualforce, and Apex controllers.
- Service: Apex or flows that coordinate work and are not owned by another
  layer.

Apex controllers are UI-owned adapters. Keep them low-logic; delegate meaningful
complexity to a service, including component-specific services when needed.

## Apex Style

- Favor minimalist, linear Apex with low ceremony.
- Do not write `private` where Apex already defaults to private.
- Match existing sharing and extension style: `inherited sharing`,
  `with sharing`, `virtual`, nested services/mocks, and small static facades.
- Prefer existing dependency injection patterns in `DML`, `Query`, and
  `TestData`.
- Keep comments sparse and useful.
- Avoid passing stateful `SObject` payloads into async work. Prefer stable Ids
  or explicitly stateless payloads.
- Avoid production compile dependencies on test or mock classes.
- If a concrete method may be overridden, mark it `virtual`; use
  `override virtual` when preserving extensibility.
- Avoid abbreviations. Code should be human readable and self-documenting.

## Apex Tests

Tests should prove behavior, artifacts, or mutations, not chase coverage.

Conventions:

- New or updated Apex unit test metadata uses API version `66.0`.
- Inspect matching `*.cls-meta.xml` files when adding or editing tests.
- Prefer lowercase `@istest`.
- Prefer inline test method annotations:
  `@istest static void testFeature_subtype() { ... }`
- Use `Assert`, never `System.assert*`.
- Every assertion needs a meaningful message.
- Use `TestData` for test records; call `mockIds()` by default when Ids matter.
- Keep setup focused on the behavior under test.
- All DML goes through `DML`.
- All query logic goes through `Query.records(...)`.
- Service tests should use mocks instead of real DML or SOQL where practical.
- Use `DMLMock`, `QueryMock`, and `QueryMock.Multiple` for dependency-injected
  assertions.

## Documentation

The docs site lives in `docs/`. Read `docs/AUTHORING.md` before adding or
editing library pages.

Core rules:

- Verify every API claim against the actual class in `force-app/bedrock/lib`.
- Apex examples follow repo test conventions.
- Each implemented library should have a docs page and nav entry.
- `Selector` is roadmap only and intentionally undocumented.
- Validate docs changes with `npm run build` in `docs/`.

## Implemented Tools

| Tool | Component guide |
|---|---|
| `TestData` | [`lib/test-data/AGENTS.md`](force-app/bedrock/lib/test-data/AGENTS.md) |
| `DML` / `DMLMock` | [`lib/dml/AGENTS.md`](force-app/bedrock/lib/dml/AGENTS.md) |
| `Query` / `QueryMock` | [`lib/query/AGENTS.md`](force-app/bedrock/lib/query/AGENTS.md) |
| `Generic` | [`lib/generic/AGENTS.md`](force-app/bedrock/lib/generic/AGENTS.md) |
| `PlatformCache` / `PlatformCacheMock` | [`lib/platform-cache/AGENTS.md`](force-app/bedrock/lib/platform-cache/AGENTS.md) |
| `RecordBuffer` | [`lib/record-buffer/AGENTS.md`](force-app/bedrock/lib/record-buffer/AGENTS.md) |
| `TriggerHandler` | [`lib/trigger-handler/AGENTS.md`](force-app/bedrock/lib/trigger-handler/AGENTS.md) |
| `Async` | [`lib/async/AGENTS.md`](force-app/bedrock/lib/async/AGENTS.md) |
| `Thread` | [`lib/thread-service/AGENTS.md`](force-app/bedrock/lib/thread-service/AGENTS.md) |
| `EventRelay` | [`lib/event/AGENTS.md`](force-app/bedrock/lib/event/AGENTS.md) |
| `Scheduler` | [`lib/scheduler/AGENTS.md`](force-app/bedrock/lib/scheduler/AGENTS.md) |
| `Pluck` | [`lib/pluck/AGENTS.md`](force-app/bedrock/lib/pluck/AGENTS.md) |
| `FeatureFlag` | [`lib/feature-flag/AGENTS.md`](force-app/bedrock/lib/feature-flag/AGENTS.md) |
| `Limiter` / `LimiterMock` | [`lib/limiter/AGENTS.md`](force-app/bedrock/lib/limiter/AGENTS.md) |

## Roadmap

`ROADMAP.md` is the cross-component index. Component roadmaps live beside the
code they describe. Treat all roadmap content as intended direction until the
source and metadata exist.

## Composition

- `TestData`, `DML`, and `Query` enable dependency injection and fast tests.
- `Pluck` provides small `Set<Id>` helpers for list-driven APIs.
- `RecordBuffer` coordinates DML staging in trigger flows.
- `TriggerHandler` coordinates domain lifecycle hooks.
- `Async`, `EventRelay`, and `Scheduler` build on the shared `Thread`,
  `Limiter`, `DML`, and `Query` patterns where appropriate.

Prefer one clear bite at a time over large speculative framework builds.
