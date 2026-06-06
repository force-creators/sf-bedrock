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
- Inspect other folders only when the task requires it. In particular,
  `force-app/main/default/classes/Async2.cls` is a prototype or scratch class,
  not part of the implemented Bedrock library unless a task explicitly brings
  it into scope.
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
- Discuss validation per task. Do not add Salesforce CLI command examples to
  this guide.

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
- Code shall be human readable and self documenting.
- Code should avoid abbreviations.

## Apex Unit Tests

Tests should prove behavior, artifacts, or mutations. Do not write tests that
exist only for coverage. Assert the thing the code is responsible for doing,
and make the proof easy to understand.

Test class conventions:

- New or updated Apex unit test metadata should use API version `56.0`. This is
  an intentional test compatibility standard even when nearby project metadata
  uses a newer source API version.
- Use the `@IsTest(testFor="ApexClass:ClassName")` annotation form for test
  classes.
- Use the `Assert` class for assertions. Do not use `System.assert*`.
- Every assertion must include a meaningful message that explains the expected
  behavior or artifact.
- When adding or changing unit tests, run the relevant Apex tests and verify
  they pass before considering the test work finished. The Salesforce CLI may
  be used for this validation; if local org or CLI access is unavailable,
  report that clearly.

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

`Async` currently exists in `force-app/bedrock/lib/async` as a minimal abstract
Apex base implementing `Queueable`, `Finalizer`, and `Database.AllowsCallouts`,
with an `AsyncException` type. Do not assume the planned framework behavior
exists in this class.

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

### Selector.Cached and PlatformCache

`Selector.Cached` is planned as an extension of the one-query selector behavior
that stores records in Salesforce Platform Cache. `PlatformCache` should be an
abstraction around Salesforce Platform Cache, used by cached selectors and any
future code that needs cache dependency injection or safer cache access.

### Async Framework

The future `Async` framework should manage Queueable work on the platform while
following the KISS principle and evolving one feature at a time. Prior versions
of this idea have supported very large queueable volume, but sf-bedrock should
start simple and grow deliberately.

This roadmap may be informed by prototype work outside `force-app/bedrock/lib`,
but prototype code is not a public Bedrock API.

Intended direction:

- `Async` is the base class for future Scheduler and Event patterns.
- `Async`, `Event`, and `Scheduler` should each have their own logical
  execution pool. Do not collapse their queues, job tracking, or policy without
  an explicit plan.
- `Async` should generally process first-in-first-out, but may support job
  priority and job bundling to maximize Queueable efficiency.
- It should use a finalizer to track execution state on `Async_Job__c`.
- `Async_Config__mdt` should control job configuration.
- Developer contracts should support no payload or `Set<Id>` payloads.
- Avoid stateful `SObject` payloads because records can change between trigger
  execution and async execution.
- The framework should attempt to bundle similar async jobs when practical.
- It should consult `LimitsService` before enqueueing or running work. If
  Queueable limits are exhausted, pause pending jobs instead of burning work or
  failing noisily.

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

### FeatureFlag

`FeatureFlag` is planned as a basic Apex/Salesforce feature management
framework. Keep it simple unless future requirements demand more.

## Implementation Philosophy

sf-bedrock should make the common enterprise-safe path easy without making the
framework feel heavy. Separation of concerns should shape all designs. Each
tool should compose with the others:

- `TestData`, `DML`, and `Query` enable dependency injection and fast tests.
- `Selector` should encapsulate query logic and build on `Query`.
- `Selector.Cached` should build on Selector and Platform Cache.
- `RecordBuffer` should coordinate DML staging in trigger flows.
- `TriggerHandler` should coordinate Bedrock lifecycle hooks around domain
  logic.
- `Async`, `Event`, and `Scheduler` should share the same async foundation.
- `Async`, `Event`, and `Scheduler` should maintain separate logical execution
  pools and use `LimitsService` to protect org health before running work.

Prefer one clear bite at a time over large speculative framework builds.
