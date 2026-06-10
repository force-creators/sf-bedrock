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

This file is both a working guide and a memory bank. It records current
implementation facts, coding preferences, and planned architecture. Do not
treat every roadmap note as an implemented contract.

- Start framework work by inspecting `force-app/bedrock/lib`. That folder is
  the source of truth for implemented Bedrock library code.
- Inspect other folders only when the task requires it. Prototype or scratch
  Apex that lives outside `force-app/bedrock/lib` is not part of the implemented
  Bedrock library unless a task explicitly brings it into scope.
- Treat the roadmap sections below as intended direction, not finalized public
  APIs. Names, schemas, metadata objects, and behavior that do not exist in
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

This section describes the current Bedrock library in `force-app/bedrock/lib`.
Inspect the code before depending on exact method behavior.

### TestData

`TestData` builds mockable and insertable Salesforce records. It uses JSON
serialization so tests can set fields that are normally read-only, such as
audit fields, and it can generate mock Ids per `SObjectType`. This is meant to
reduce bloated unit tests where unrelated setup dominates runtime.

Current shape:

- Fluent builder around an `SObjectType`.
- `put(SObjectField, Object)` stores field values for generated records.
- `count(Integer)` controls how many records `build()` returns.
- `mockIds()` assigns synthetic Ids using the object's key prefix.
- Relationship values can be provided as `SObject` instances.

### DML and DMLMock

`DML` is the DML dependency injection layer. It exposes static methods that
delegate to an injectable service instance. Production behavior performs normal
Apex DML. Tests can use `DML.setMock(...)` with `DMLMock`.

Current shape:

- `DML` extends `DML.Service`.
- `DML.Service` exposes virtual insert, update, upsert, delete, and undelete
  methods.
- `DML.upsertRecords(...)` supports both plain upsert and upsert with an
  external Id field.
- `DMLMock` records insert, update, upsert, delete, and undelete calls in
  public list properties.

### Query and QueryMock

`Query` is the query dependency injection layer. It provides a static facade
over a virtual query implementation so test code can replace query behavior.

Current shape:

- `Query.records(List<SObject>)` delegates to the active query instance.
- Base `Query.query(...)` returns the provided records.
- `QueryMock` can return a fixed record or record list.
- `QueryMock.Multiple` can return different result sets over sequential calls
  and throws when no staged result remains.

### Generic

`Generic` is the helper for generic JSON and unstructured data. It is intended
as the toolkit for turning generic data into strongly typed Apex contracts and
for parsing or building complex JSON payloads.

Current shape:

- Construct from empty state, a JSON string, or `Map<String, Object>`.
- Read values by path, including list-style path segments.
- Coerce read values to common primitive, collection, or typed Apex targets.
- Write values by path into nested maps.
- Serialize back to JSON.
- Convert generic data into typed `SObject` records.
- Override `mapping()` and `transform()` for reusable transformations.

### PlatformCache and PlatformCacheMock

`PlatformCache` is the cache dependency injection layer for Salesforce Platform
Cache. It provides small `Org` and `Session` adapters so production code can
use platform cache directly while tests can substitute a mock partition.

Current shape:

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

Testing notes:

- Tests should usually verify org and session behaviors in distinct units such
  as `testOrg_get` and `testSession_put`, rather than combining the entire
  happy path in one method.
- When mocking, remember that the current registry is partition-name based, so
  direct org/session adapters and subclasses that share a partition name will
  use the same registered mock.

### RecordBuffer

`RecordBuffer` stages DML between services in a trigger context. It is designed
to avoid repeated DML work and reduce recursion risk when multiple services
update the same object type in the same trigger flow.

Current shape:

- Maintains a stack of trigger contexts.
- Lazily starts a context when code stages or reads records without calling
  `start()` first.
- Stages inserts when records have no Id.
- Stages updates in a `Map<Id, SObject>` when records have Ids.
- Groups staged work by `SObjectType`.
- Includes helpers for retrieving staged update records by Id; inspect edge
  behavior before relying on null or empty inputs.
- `flush()` merges inserts and updates by object type and calls
  `DML.upsertRecords(...)` once per type.

### TriggerHandler

`TriggerHandler` is a lightweight trigger handler framework. It coordinates
Bedrock tools around the domain layer without forcing a heavy trigger pattern.

Current shape:

- `run()` exits unless `Trigger.isExecuting`.
- Starts `RecordBuffer` before dispatch and flushes it after dispatch.
- Dispatches all standard trigger operations to protected virtual hooks.
- Exposes empty hook methods for before/after insert, update, delete, and
  undelete.
- Is intentionally extensible so other frameworks or setup/teardown steps can
  be added by subclasses.

### Async

`Async` in `force-app/bedrock/lib/async` is an implemented Queueable-based
async framework, not just a base class. It processes record work in chains of
Queueables tracked on the `Async__c` custom object. The pieces below exist
today; inspect the code before depending on exact behavior, and note that some
declared entry points (`stage`, `flush`) are still stubs.

Current shape:

- `Async` is a `virtual` class implementing `Queueable` and
  `Database.AllowsCallouts`. Subclasses override `execute(Set<Id> ids)`.
- Three injectable service singletons drive behavior: `Async.jobs`
  (`JobService`), `Async.work` (`WorkService`), and `Async.queries`
  (`QueryService`). `Async.setMock(AsyncMock)` swaps all three for tests.
- `Async.enqueue(Type, List<SObject>)` and `Async.enqueue(Type, Set<Id>)` create
  one `Async__c` work item per record Id (via `Pluck.ids`) in `Pending` status,
  tagged with the current request's thread id and the target Apex type.
- `Async.stage(...)` and `Async.flush()` are declared but currently empty
  placeholders for a future staging path.
- `AsyncTrigger` on `Async__c` runs `AsyncTriggerHandler` (extends
  `TriggerHandler`). After insert it starts a thread; after update it re-enqueues
  when `AsyncFilters.shouldRetry` detects an `Error` row flipped back to
  `Pending`.
- `AsyncThread` is a Queueable that adopts a thread id and asks
  `jobs.enqueueNextJob()` to dispatch the next pending work for that thread.
- `JobService.enqueueNextJob()` selects the next pending work item FIFO
  (`ORDER BY Priority__c DESC, CreatedDate ASC`), reads `Async_Config__mdt` for
  the batch size (default 5), pulls a matching batch of same-Apex work items,
  instantiates the Apex job by name, and enqueues it as `Running`.
- `Async.JobWatcher` (a `Finalizer`) marks the batch `Done` and chains the next
  job on success, or records `Error` with truncated message/stack trace and
  re-enqueues on failure.
- `WorkService` owns the `Async__c` status transitions (`create`, `running`,
  `complete`, `fail`, `retry`) through `DML`. `QueryService` owns all
  `Async__c` and `Async_Config__mdt` reads through `Query`.
- `AsyncMock` provides test subclasses of the three services, including a
  `canEnqueue()` toggle and a bounded `maximumQueueableStackDepth` thread start.
- `Async.AsyncException` is the framework's error type.

Schema: this framework relies on the `Async__c` object (fields `Apex__c`,
`Record_Id__c`, `Status__c`, `Thread__c`, `Priority__c`, `Error_Message__c`,
`Error_Stack_Trace__c`) and the `Async_Config__mdt` type (`Apex__c`,
`Batch_Size__c`), both under `force-app/bedrock/lib/async/objects`.

### Pluck

`Pluck` is a small static utility for pulling `Set<Id>` values out of record
lists, used by `Async` when turning records into work items.

Current shape:

- `Pluck.ids(List<SObject>)` collects non-null record Ids.
- `Pluck.ids(SObjectField, List<SObject>)` collects non-null Ids from a lookup
  or reference field.

### FeatureFlag

`FeatureFlag` provides feature-toggle lookups backed by `Feature_Flag__mdt`.
It caches lookups by name for the current transaction and exposes test-only
helpers to seed or clear cached values.

Current shape:

- `isEnabled(String)` fails closed for blank names and missing records.
- `get(String)` reads `Feature_Flag__mdt` by `Name__c` and caches the result
  in memory.
- `set(String, Boolean)` is test-visible and seeds the cache directly.
- `clearCache()` is test-visible and clears the in-memory cache.

## Roadmap and Proposed Tools

These concepts capture intended architecture. They are not finalized APIs.
Agents should preserve the intent, inspect current code before building, and
ask before locking names, schemas, or behavior that has not been implemented.

### Selector

Selector is the planned query encapsulation pattern. The base selector should
make simple queries testable and reusable while building on `Query`.

A one-query selector variant is planned but not named yet. Possible names
include `Selector.OneTime`, `Selector.Once`, or `Selector.Gateway`. The intended
behavior is:

- Query by a fixed set of Id values.
- Store results in `Map<Id, SObject>`.
- Return cached records when the same Id is requested again.
- Avoid repeating a query for records already loaded.

Do not choose the final API name without asking. A future implementation should
probably compare the readability of `Once` against the architectural meaning of
`Gateway`.

### Selector.Cached

`Selector.Cached` is planned as an extension of the one-query selector behavior
that stores records in Salesforce Platform Cache by building on the implemented
`PlatformCache` abstraction.

### Async Framework

The core `Async` framework is implemented (see the Implemented Tools section).
The notes below capture intended direction for the parts that are not yet
built. The framework should keep following the KISS principle and evolve one
feature at a time. Prior versions of this idea have supported very large
queueable volume, but sf-bedrock should grow deliberately from the current
simple base.

Already implemented: thread-based Queueable chaining, `Async__c` work-item
tracking via a `Finalizer`, FIFO dispatch with `Priority__c`, batch bundling of
same-Apex work items sized by `Async_Config__mdt.Batch_Size__c`, `Set<Id>`
payload contracts, and trigger-driven retry of failed work. Note the
implementation tracks work on `Async__c`, not the earlier proposed
`Async_Job__c` name.

Remaining intended direction:

- `Async` should remain the base class for the future Scheduler and Event
  patterns.
- `Async`, `Event`, and `Scheduler` should each keep their own logical
  execution pool. Do not collapse their queues, job tracking, or policy without
  an explicit plan.
- Flesh out the stubbed `stage(...)` / `flush()` staging path so callers can
  batch work items before enqueueing a thread.
- Continue to avoid stateful `SObject` payloads because records can change
  between trigger execution and async execution; prefer the implemented
  `Set<Id>` contract.
- Async should consult `LimitsService` (not yet built) before enqueueing or
  running work. If Queueable limits are exhausted, pause pending jobs instead of
  burning work or failing noisily.

### Event

`Event` is planned as a stateless event-driven async layer built on top of
`Async`.

Intended direction:

- Support platform-event style `List<SObject>` payloads and generic
  `List<Map<String, Object>>` payloads.
- Guard `List<SObject>` usage so only platform events, whose API names contain
  `__e`, are accepted.
- Process events strictly first-in-first-out. Do not introduce priority or
  reordering into Event.
- Bundling may be supported, but only when explicitly enabled by configuration.
- Use async processing and finalizer tracking to avoid the silent-failure
  problem common with Platform Events.
- Consult `LimitsService` before publishing events or starting event work when
  platform limits may be at risk.
- Track executions with `Event_Job__c`.
- Configure behavior with `Event_Config__mdt`.

### Scheduler

`Scheduler` is planned as an async-backed scheduler framework that avoids
consuming one Salesforce scheduled job slot per logical scheduled task.

Intended direction:

- Use a small fixed number of Salesforce scheduled jobs, likely three slots.
- Run logical jobs from `Scheduler_Config__mdt`.
- Support cadence rules such as every X minutes in five-minute intervals, every
  X hours, and every X days.
- Use `Scheduler_Job__c` to track due work and recovery state.
- Enqueue due work async.
- Pass a scheduler "tic" through constructors as the frame of reference for
  the next scheduler run.
- Maintain Scheduler as its own logical execution pool, separate from Async and
  Event.
- Design defensively for Salesforce outages and missed windows.

### LimitsService

`LimitsService` is planned as the shared limit-awareness layer for Async and
its extensions. It should help the framework decide whether it is safe to
enqueue Queueables, publish events, or start pending work.

Intended direction:

- Expose current org and transaction limit usage in a testable service.
- Help `Async`, `Event`, and `Scheduler` decide when to run, pause, or resume.
- If Queueable limits are exhausted, all framework job pools should pause
  pending work rather than attempting unsafe execution.
- Each framework should have a scheduled monitor that runs about every 15
  minutes, checks whether enough limits exist, and restarts paused work when it
  is safe. If limits are still exhausted, it should wait for the next monitor
  run.
- Keep this human/developer-first: prefer clear state, explainable behavior,
  and maintainable recovery over opaque automation.

## Implementation Philosophy

sf-bedrock should make the common enterprise-safe path easy without making the
framework feel heavy. Separation of concerns should shape all designs. Each
tool should compose with the others:

- `TestData`, `DML`, and `Query` enable dependency injection and fast tests.
- `Pluck` provides the small `Set<Id>` helpers that feed list-driven APIs like
  `Async.enqueue`.
- `Selector` should encapsulate query logic and build on `Query`.
- `Selector.Cached` should build on Selector and Platform Cache.
- `RecordBuffer` should coordinate DML staging in trigger flows.
- `TriggerHandler` should coordinate Bedrock lifecycle hooks around domain
  logic; `Async` already builds on it via `AsyncTriggerHandler`.
- `Async` runs on `DML`, `Query`, and `Pluck` today; `Event` and `Scheduler`
  should share that same async foundation.
- `Async`, `Event`, and `Scheduler` should maintain separate logical execution
  pools and use `LimitsService` to protect org health before running work.

Prefer one clear bite at a time over large speculative framework builds.
