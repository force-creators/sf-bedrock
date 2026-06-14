# sf-bedrock Agent Guide

sf-bedrock is a Salesforce base-org/domain/service/selector layer intended to make Apex
development more stable, testable, scalable, and readable. The core problem
space is Salesforce automation architecture: dependency injection for data
access and DML, efficient test data, trigger hygiene, async safety, and
enterprise patterns that can grow without making everyday development heavy.

The mission is developer-first and human-maintainable: high-service automation
that protects the org while remaining understandable to the people who own it.

The owner does not trust AI code blindly. Future agents should help in small,
inspectable steps, explain tradeoffs, and keep implementation work easy for a
human Salesforce engineer to understand.

## How To Use This Guide

This file is both a working guide and a memory bank. It records project-wide
implementation facts and coding preferences. Per-component detail is split out
so agents read only the context a task needs:

- This root `AGENTS.md` holds project-wide philosophy and conventions
  (architecture layers, Apex style, testing rules, the Salesforce MCP workflow,
  documentation rules).
- Each implemented library has its own guide at
  `force-app/bedrock/lib/<component>/AGENTS.md` describing that tool's current
  shape and usage. Read the component guide for the tool you are working on
  rather than loading every tool's detail up front.
- Planned and future architecture lives in `ROADMAP.md` (cross-cutting
  sequencing and shared principles) and in each component's
  `force-app/bedrock/lib/<component>/ROADMAP.md`. Do not treat a roadmap note as
  an implemented contract.

Working norms:

- Start framework work by inspecting `force-app/bedrock/lib`. That folder is
  the source of truth for implemented Bedrock library code.
- Inspect other folders only when the task requires it. Prototype or scratch
  Apex that lives outside `force-app/bedrock/lib` is not part of the implemented
  Bedrock library unless a task explicitly brings it into scope.
- Treat roadmap files as intended direction, not finalized public APIs. Names,
  schemas, metadata objects, and behavior that do not exist in
  `force-app/bedrock/lib` need an explicit plan before implementation.
- Preserve the user's local work. If unrelated files are dirty or untracked,
  ignore them unless they affect the task.

## Working Rules

- Use a plan-first posture for meaningful framework work. Tiny fixes under
  roughly 10 lines may be implemented directly with good judgment.
- Do not blindly implement large features. Read the relevant code, propose
  bite-sized work, and keep changes understandable.
- Existing public Apex APIs may evolve carefully, but public names or
  signatures should change only after a plan calls out the compatibility
  impact.
- Current rough edges may be noticed, but do not fix unrelated issues unless
  they are clearly in scope or qualify as a tiny obvious fix.
- Prefer the smallest useful change set. Keep edits narrow, avoid broad repo
  searches, and do not rewrite unrelated files while working a local task.

## Token Efficiency

- Prefer Apex and JavaScript work. Do not create new Salesforce metadata files
  in the agent unless the task explicitly requires it.
- If a task needs a new object, field, custom metadata type, or similar schema
  file, tell the user what is needed and let them scaffold it manually.
- Keep output tight. Prefer the smallest relevant file set, the shortest
  useful explanation, and the narrowest validation possible.
- When test work is involved, change only the targeted test method or helper,
  deploy only the touched source, and run only the specific tests that cover
  the change.

### Context & Tool-Output Hygiene

The biggest token drain on this repo is not the guides — it is broad searches,
whole-file reads, and verbose command output piling up in the live context. Keep
that tail small:

- Read narrowly. Prefer targeted reads (a known file, a line range, a specific
  symbol) over reading large files end to end to use a few lines.
- Search for conclusions, not dumps. For a broad "where is X / what calls Y"
  sweep across many files, prefer a sub-agent search that returns the answer
  rather than pulling every match into the main context.
- Keep commands quiet. Scope output to what matters: `git log --oneline -10`
  not bare `git log`; run a single named Apex test, not the whole class or
  suite; avoid dumping whole files to stdout. Use the dedicated file/search
  tools instead of `cat`/`sed`/`echo`.
- Load component context on demand. Read the one
  `force-app/bedrock/lib/<component>/AGENTS.md` (and `ROADMAP.md`) the task needs
  rather than surveying every tool up front.

### Salesforce MCP Validation

Use `sf-bedrock` as the target org alias for Salesforce org work in this repo.
Do not rely on a default org being configured in the agent environment.

Prefer the Salesforce DX MCP tools over raw Salesforce CLI commands when an
equivalent tool is available. The expected MCP tool invocations are:

- Deploy metadata: `mcp__salesforce_dx.deploy_metadata`
- Retrieve metadata: `mcp__salesforce_dx.retrieve_metadata`
- Run Apex tests: `mcp__salesforce_dx.run_apex_test`
- Run SOQL queries: `mcp__salesforce_dx.run_soql_query`
- Resolve an unclear org alias: `mcp__salesforce_dx.get_username`
- Resume a long-running org operation: `mcp__salesforce_dx.resume_tool_operation`

Validation workflow:

- Do not run Salesforce Code Analyzer, including
  `mcp__salesforce_dx.run_code_analyzer`, `query_code_analyzer_results`,
  `list_code_analyzer_rules`, or raw CLI analyzer commands. It is too noisy
  and token-expensive for this repo's preferred workflow.
- After changing Apex or Salesforce metadata, deploy the changed source and
  validate the result before considering the edit complete. Use the MCP
  `mcp__salesforce_dx.deploy_metadata` tool for deploy operations when a real
  deploy is intended.
- If validation reports compile, metadata, or test errors caused by the current
  task, fix them autonomously and rerun the deploy once the change is narrow and
  targeted.
- Treat Salesforce deploy errors as the compiler's source of truth. Update the
  code in response to concrete deploy feedback rather than guessing around it.
- If Salesforce org access fails because of keychain, org auth, or sandbox
  permissions, retry with the approved escalation flow when using a CLI
  fallback. Only report validation as blocked after the MCP tool or escalated
  fallback also cannot access the org or the org itself is unavailable.
- Brief CLI command examples are allowed in this guide only when there is no
  MCP equivalent or when they prevent repeated validation mistakes. Keep CLI
  output tight and scoped to the files or checks that matter.

### Salesforce Tool Timeout Policy

To avoid wasting tokens on slow Salesforce org responses:

- For synchronous Salesforce MCP tools or CLI fallback commands, allow up to 10
  seconds of waiting when the tool supports bounded waiting.
- If the operation does not complete within 10 seconds, stop polling and report
  that it is taking too long.
- After 10 seconds, provide the exact MCP tool name or fallback command so the
  user can run it directly if they want to keep waiting.
- Do not continue repeated progress checks after the 10 second limit.
- Do not switch to async or resume-based workflows unless the user explicitly
  asks for that.

## Architecture Layers

Separation of concerns is the primary architectural philosophy. Future agents
should preserve clear layer boundaries and avoid moving logic across layers just
because it is convenient in the moment.

Think of a Salesforce org in five distinct layers:

- Schema: `SObject` definitions, metadata, custom settings, and configuration
  records that define system shape.
- Domain: `SObject` automations, including before/after save flows, Apex
  triggers, Process Builder, and record lifecycle behavior.
- Selector: query logic and reusable data access patterns.
- UI Layer: Lightning components, Flexipages, Visualforce, Apex controllers,
  and anything else "on the glass."
- Service: flows or Apex that coordinate work, call other Apex, and are not
  explicitly owned by another layer.

Apex controllers are the important deviation: treat them as UI-owned adapters
to the service layer. Controllers should stay low-logic and beholden to the
component they serve. They may return simple query results or delegate in one
or two lines, but meaningful complexity belongs in an Apex service. If
`MyComponent` and `MyComponentController` are complex, introduce a
`MyComponentService` dedicated to that component rather than letting controller
logic grow.

## Apex Style

- Favor minimalist, linear Apex with maximal readability and low ceremony.
- Do not write `private` where Apex defaults already make members private.
- Match existing sharing and extension style: `inherited sharing`,
  `with sharing`, `virtual`, nested service/mock classes, and small static
  facades where appropriate.
- Prefer the dependency injection patterns already present in `DML`, `Query`,
  and `TestData`.
- Keep comments sparse and useful. Add a comment only when it removes real
  ambiguity.
- Avoid broad refactors, speculative abstractions, and cleverness that makes
  the framework harder to reason about.
- Avoid passing stateful `SObject` payloads into async work. Prefer stable
  identifiers or explicitly stateless payloads.
- Avoid production compile dependencies on test or mock classes. When a mock
  extends a production abstraction, production APIs should accept the
  abstraction type, not the mock type.
- If a concrete method may be overridden by subclasses, mark it `virtual`. When
  overriding a method and preserving extensibility, use `override virtual`.
- Code shall be human readable and self documenting.
- Code should avoid abbreviations.

## Apex Unit Tests

Tests should prove behavior, artifacts, or mutations. Do not write tests that
exist only for coverage. Assert the thing the code is responsible for doing,
and make the proof easy to understand.

Test class conventions:

- New or updated Apex unit test metadata should use API version `66.0`.
- Always inspect and update the matching `*.cls-meta.xml` file when adding or
  editing an Apex unit test. Verify that the metadata API version remains
  `66.0`.
- Prefer lowercase `@istest` in this repo.
- For test methods, prefer inline annotation style:
  `@istest static void testFeature_subtype() { ... }`
- Class-level `@istest` and `@istest(testFor=...)` are allowed when they add
  clarity or intent, but method annotations should still use the inline style.
- Use the `Assert` class for assertions. Do not use `System.assert*`.
- Every assertion must include a meaningful message that explains the expected
  behavior or artifact.
- When adding or changing unit tests, deploy the changed production classes,
  mocks, and tests before running the test. If a new test references a new
  helper or mock class, include that helper or mock in the deploy source so the
  test compiles in the org.
- When a test changes, prefer running only the specific test method or the
  smallest relevant test set rather than the entire class or suite.
- After the deploy succeeds, run the relevant Apex test by name with
  `mcp__salesforce_dx.run_apex_test` against `sf-bedrock` and verify it passes
  before considering the test work finished. Fix task-related test failures
  autonomously and rerun the test.

Metadata version conventions:

- Apex unit test classes should use API version `66.0`.
- Non-test Apex classes and other metadata should use API version `65.0` unless
  a task explicitly requires something else.

Salesforce org workflow notes:

- Use the `sf-bedrock` alias explicitly in every Salesforce MCP tool invocation.
- Use CLI fallbacks only when an MCP tool is unavailable for the needed
  operation, such as check-only deploy validation.
- If a CLI fallback cannot find the alias or auth inside the sandbox, retry
  with the approved escalation flow before treating validation as blocked. In
  this repo, that commonly means sandboxed access cannot reach the stored org
  auth even though the org itself is available.

Test data conventions:

- Use `TestData` for unit test records.
- When building mock data, call `mockIds()` by default.
- Keep data setup focused on the behavior under test. Avoid expensive,
  unrelated setup.

Example:

```apex
List<SObject> accounts = new TestData(Account.sObjectType)
    .put(Account.Name, 'ABC')
    .mockIds()
    .count(5)
    .build();
```

When a test needs a typed record, cast the result at the usage point:

```apex
Account account = (Account) new TestData(Account.sObjectType)
    .put(Account.Name, 'ABC')
    .mockIds()
    .build()[0];
```

DML and query conventions:

- All DML should go through `DML`.
- All query logic should go through `Query.records(...)`.
- Unit tests should use mocks instead of real DML or SOQL when testing service
  behavior.
- Use `DMLMock` to capture DML calls and assert the operation, count, record
  type, and important field mutations.
- Use `QueryMock` for a single query result.
- Use `QueryMock.Multiple` when more than one query response is needed. It
  returns values in the same order they are staged.

## Documentation

The docs site lives in `docs/` (Astro) and renders one page per Bedrock library
under `docs/src/pages/`. The canonical authoring guide is `docs/AUTHORING.md` —
read it before adding or editing a page. Core rules:

- Every library page follows one fixed structure: `Overview → Quickstart →
  Examples` (plus optional tool-specific sections) `→ Testing → How It Works →
  Public API → Notes & Edge Cases`. The first three and the last headers are
  identical on every page; tool-specific sections sit in the middle band.
- Write for junior-to-mid Salesforce developers. Lead with usage so a reader can
  start building on the first screen, and keep mechanism, the API reference
  table, and framework philosophy lower on the page or in short `>` asides.
- Do not embellish, and never use the word "gotcha" — the closing section is
  always named "Notes & Edge Cases".
- Verify every API claim (signatures, access modifiers, behavior) against the
  actual class in `force-app/bedrock/lib` before documenting it. This is a
  developer-trust project; unverified behavior must not be presented as fact.
  Remember the Apex default: a member with no access modifier is private.
- Apex examples follow the repo test conventions: lowercase `@istest`, the
  `Assert` class with meaningful messages, `TestData` for records, DML through
  `DML`, and queries through `Query.records(...)`.
- Each implemented library in `force-app/bedrock/lib` should have a page and a
  nav entry in `docs/src/data/docs-navigation.ts`. `Pluck` lives under the
  "Other" group; `Selector` is roadmap (no Apex yet) and is intentionally
  undocumented. Validate page changes with `npm run build` in `docs/`.

## Implemented Tools

Each implemented Bedrock library has its own component guide next to its code.
Read the relevant `force-app/bedrock/lib/<component>/AGENTS.md` for current
shape and usage before depending on exact method behavior; do not load every
tool's detail up front.

| Tool | Component guide |
|---|---|
| `TestData` | [`lib/test-data/AGENTS.md`](force-app/bedrock/lib/test-data/AGENTS.md) |
| `DML` / `DMLMock` | [`lib/dml/AGENTS.md`](force-app/bedrock/lib/dml/AGENTS.md) |
| `Query` / `QueryMock` | [`lib/query/AGENTS.md`](force-app/bedrock/lib/query/AGENTS.md) |
| `Generic` | [`lib/generic/AGENTS.md`](force-app/bedrock/lib/generic/AGENTS.md) |
| `PlatformCache` / `PlatformCacheMock` | [`lib/platform-cache/AGENTS.md`](force-app/bedrock/lib/platform-cache/AGENTS.md) |
| `RecordBuffer` | [`lib/record-buffer/AGENTS.md`](force-app/bedrock/lib/record-buffer/AGENTS.md) |
| `TriggerHandler` | [`lib/trigger-handler/AGENTS.md`](force-app/bedrock/lib/trigger-handler/AGENTS.md) |
| `Async` (framework) | [`lib/async/AGENTS.md`](force-app/bedrock/lib/async/AGENTS.md) |
| `Thread` | [`lib/thread-service/AGENTS.md`](force-app/bedrock/lib/thread-service/AGENTS.md) |
| `Scheduler` | [`lib/scheduler/AGENTS.md`](force-app/bedrock/lib/scheduler/AGENTS.md) |
| `Pluck` | [`lib/pluck/AGENTS.md`](force-app/bedrock/lib/pluck/AGENTS.md) |
| `FeatureFlag` | [`lib/feature-flag/AGENTS.md`](force-app/bedrock/lib/feature-flag/AGENTS.md) |
| `Limiter` / `LimiterMock` | [`lib/limiter/AGENTS.md`](force-app/bedrock/lib/limiter/AGENTS.md) |

## Roadmap

Planned and future work is split the same way. `ROADMAP.md` at the repo root
holds the cross-cutting sequencing and the shared "keep the pools separate"
principle; each framework's detailed roadmap lives in
`force-app/bedrock/lib/<component>/ROADMAP.md` (Async features + Console UI,
Thread/Multithreading, Limiter, Scheduler, Event, Selector). Treat
those files as intended direction, not finalized public APIs. Names, schemas,
and behavior described there are not finalized; inspect current code and ask
before locking them.

## Implementation Philosophy

sf-bedrock should make the common enterprise-safe path easy without making the
framework feel heavy. Separation of concerns should shape all designs. Each
tool should compose with the others:

- `TestData`, `DML`, and `Query` enable dependency injection and fast tests.
- `Pluck` provides the small `Set<Id>` helpers that feed list-driven APIs like
  `Async.enqueue`.
- `RecordBuffer` coordinates DML staging in trigger flows.
- `TriggerHandler` coordinates Bedrock lifecycle hooks around domain logic;
  `Async` already builds on it via `AsyncTriggerHandler`.
- `Async` runs on `DML`, `Query`, `Pluck`, and `Thread` today.

Prefer one clear bite at a time over large speculative framework builds. Planned
extensions that build on these tools are tracked in the component `ROADMAP.md`
files.
