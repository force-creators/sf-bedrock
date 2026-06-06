---
layout: ../layouts/DocsLayout.astro
title: Query | sf-bedrock docs
description: Technical documentation and usage examples for the sf-bedrock Query dependency-injection facade and its QueryMock test double.
eyebrow: Dependency Injection
heading: Query
lede: A tiny dependency-injection facade that sits between your code and the records it consumes — so production code runs real queries while tests swap in mock results, with no database access and no SeeAllData.
sections:
  - label: Purpose
    href: "#purpose"
  - label: How It Works
    href: "#how-it-works"
  - label: Public API
    href: "#public-api"
  - label: Examples
    href: "#examples"
  - label: Testing with QueryMock
    href: "#testing-with-querymock"
  - label: Multiple Mock Responses
    href: "#multiple-mock-responses"
  - label: Gotchas & Testing Notes
    href: "#gotchas-and-testing-notes"
---

## Purpose

`Query` is a dependency-injection (DI) facade for the records your code reads.
Instead of consuming a `List<SObject>` directly, you route it through
`Query.records(...)`. In production that call returns the list unchanged. In a
test you first inject a `QueryMock`, and the same call returns whatever records
the mock was primed with.

The point is **seam, not transformation.** `Query` does not run SOQL, filter,
sort, or reshape anything. Its only job is to give you a single, swappable point
where a test can substitute mock data for the real thing — the classic *seam*
that makes otherwise hard-to-test code testable.

**Use `Query` when** a unit needs a collection of records and you want tests to
control exactly which records it sees, without inserting rows, running SOQL, or
relying on org data. Pair it with [`TestData`](/test-data) to build the mock
records.

**Do not reach for `Query` when** you actually need querying behavior — WHERE
clauses, ORDER BY, relationship traversal, governor-aware chunking. `Query`
provides none of that. It is a pass-through indirection layer, not a query
builder or a selector framework.

## How It Works

Three ideas explain everything `Query` does.

### 1. It is a facade over a single swappable instance

`Query` holds one **private static** field, `instance`, initialized to a plain
`new Query()`. Every caller goes through the **static** entry point
`Query.records(records)`, which simply delegates to `instance.query(records)`:

```apex
// inside Query.cls
public static List<SObject> records(List<SObject> records) {
    return instance.query(records);
}
```

The default `query(...)` is the identity function — it returns the list it was
given:

```apex
public virtual List<SObject> query(List<SObject> records) {
    return records;
}
```

So in production, `Query.records(myRecords)` returns `myRecords`, untouched.

### 2. Tests inject a subclass (dependency injection)

The `query(...)` method is `virtual`, and `instance` can be replaced through the
`@TestVisible` method `setMock(Query mock)`. A test injects a subclass whose
`query(...)` override ignores its input and returns canned records instead. This
is textbook **dependency injection** combined with the **mock** pattern: the
collaborator (`instance`) is supplied from outside rather than hard-coded, so
the test decides what it does.

```apex
Query.setMock(new QueryMock(mockedRecords));
// from now on, Query.records(anything) returns mockedRecords
```

`setMock` is `@TestVisible`, meaning it is private to production code but callable
from test classes. Production code can never accidentally swap the instance.

### 3. Nothing touches the database

`Query` performs no DML and no SOQL. The default path returns its argument; the
mock path returns a list you handed it. That is what makes a unit built around
`Query` fast and isolated — no rows consumed, no triggers fired, no org data
dependency.

## Public API

The DI facade lives in two classes: `Query` (the seam) and `QueryMock` (the test
double, with a nested `Multiple` variant).

> **A note on "properties":** Neither `Query` nor `QueryMock` exposes any public
> properties. In Apex, a member declared with **no access modifier is private** —
> so `Query`'s `instance` field and `QueryMock`'s `records`/`index` fields are
> all private internal state. The supported surface is the methods below.

### `Query`

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| `query` | `query(List<SObject> records)` | `List<SObject>` | Instance method, `virtual`. Default implementation returns its argument unchanged. Overridden by mocks. You rarely call this directly — call `records(...)` instead. |
| `records` | `records(List<SObject> records)` | `List<SObject>` | **Static** entry point. Delegates to the current instance's `query(...)`. This is what production code calls. |

> `setMock(Query mock)` is **not public** — it is `@TestVisible static`, so it is
> only reachable from test code. It replaces the active instance and is the
> injection point for mocking. It is documented here because it is the mechanism
> tests rely on, but it is not part of the production-facing API.

### `QueryMock` (extends `Query`)

A drop-in `Query` whose `query(...)` returns a fixed list regardless of input.

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| Constructor | `QueryMock()` | `QueryMock` | Default constructor. Returns `null` from `query(...)` until records are supplied via another constructor. |
| Constructor | `QueryMock(SObject record)` | `QueryMock` | Convenience constructor that wraps a single record into a one-element list. |
| Constructor | `QueryMock(List<SObject> records)` | `QueryMock` | The common case: primes the mock to return exactly this list. |
| `query` | `query(List<SObject> ignore)` | `List<SObject>` | `override`. Ignores its argument and returns the primed records. |

### `QueryMock.Multiple` (inner class, extends `QueryMock`)

A mock that returns a **different** list on each successive call — useful when the
unit under test calls `Query.records(...)` more than once.

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| Constructor | `Multiple()` | `Multiple` | Creates an empty queue of responses. |
| `add` | `add(List<SObject> records)` | `Multiple` | Appends one response list to the queue and returns `this` (fluent). Call once per expected query. |
| `query` | `query(List<SObject> ignore)` | `List<SObject>` | `override`. Returns the next queued list and advances an internal index. Throws `QueryMockException` if called more times than there are queued responses. |

### `QueryMock.QueryMockException` (inner class, extends `Exception`)

Thrown by `Multiple.query(...)` when the unit asks for more responses than were
queued. Its presence is intentional: an unexpected extra query is a test failure,
not a silent `null`.

## Examples

### Production: a unit that consumes records through the seam

The pattern is to route the records a unit operates on through
`Query.records(...)`. In production this is a no-op pass-through; the payoff comes
in the test.

```apex
public with sharing class AccountTierService {
    public Map<Id, String> assignTiers(List<Account> accounts) {
        Map<Id, String> tiers = new Map<Id, String>();
        for (Account a : (List<Account>) Query.records(accounts)) {
            tiers.put(a.Id, a.AnnualRevenue >= 1000000 ? 'Enterprise' : 'SMB');
        }
        return tiers;
    }
}
```

### Default behavior: pass-through when no mock is set

With no mock injected, `records(...)` returns the **same list instance** it was
given. This is exactly what `QueryTest.testRecords_returnsInputWhenNoMockSet`
asserts.

```apex
List<SObject> records = new TestData(Account.sObjectType)
    .put(Account.Name, 'Bedrock Query')
    .count(2)
    .build();

List<SObject> result = Query.records(records);

Assert.areEqual(2, result.size(), 'Default Query returns all provided records.');
Assert.areEqual('Bedrock Query', ((Account) result[0]).Name, 'Values preserved.');
Assert.areEqual(records, result, 'Default implementation passes through the same list.');
```

> Note the last assertion: the default `query(...)` returns the *identical* list
> reference, not a copy. Do not rely on `Query` to defensively clone your data.

## Testing with QueryMock

This is where `Query` earns its place. The recipe is always the same:

1. Build the records the unit should "see" (with [`TestData`](/test-data) or
   plain constructors).
2. Inject them with `Query.setMock(new QueryMock(...))`.
3. Exercise the unit. Every `Query.records(...)` call now returns your records.

### Stub a single response

Drawn directly from `QueryTest.testRecords_usesMockWhenSet`: once a mock is set,
`records(...)` returns the mock's list and **ignores its own argument**.

```apex
List<SObject> inputRecords = new TestData(Account.sObjectType)
    .put(Account.Name, 'Input')
    .count(1)
    .build();
List<SObject> mockRecords = new TestData(Account.sObjectType)
    .put(Account.Name, 'Mocked')
    .count(2)
    .build();

Query.setMock(new QueryMock(mockRecords));

List<SObject> result = Query.records(inputRecords);   // inputRecords is ignored

Assert.areEqual(2, result.size(), 'Returns the mock result, not the input list.');
Assert.areEqual('Mocked', ((Account) result[0]).Name, 'Records come from the mock.');
Assert.areEqual(mockRecords, result, 'Returns the exact list supplied by QueryMock.');
```

### Stub a single record

When the unit needs just one record, the single-record constructor saves you from
wrapping it in a list yourself.

```apex
Account account = (Account) new TestData(Account.sObjectType)
    .put(Account.Name, 'Solo')
    .mockIds()
    .build()[0];

Query.setMock(new QueryMock(account));   // wrapped into a one-element list

List<SObject> result = Query.records(new List<SObject>());
Assert.areEqual(1, result.size(), 'Single-record constructor yields one record.');
```

### A realistic service test

The full shape: build mock records, inject, call the service, assert — no DML and
no SOQL anywhere.

```apex
@IsTest
static void categorizesHighValueAccounts() {
    List<Account> accounts = (List<Account>) new TestData(Account.sObjectType)
        .put(Account.Name, 'Enterprise Co')
        .put(Account.AnnualRevenue, 10000000)
        .mockIds()
        .count(2)
        .build();

    Query.setMock(new QueryMock(accounts));

    AccountTierService service = new AccountTierService();
    // The service's own Query.records(...) call now returns the mocked accounts.
    Map<Id, String> tiers = service.assignTiers(
        (List<Account>) Query.records(new List<Account>())
    );

    for (Account a : accounts) {
        Assert.areEqual('Enterprise', tiers.get(a.Id), 'High revenue maps to Enterprise.');
    }
}
```

### Empty results

To prove a unit handles "no records," inject an empty list. (The default
`QueryMock()` constructor instead returns `null`, which is usually not what you
want — see [Gotchas](#gotchas-and-testing-notes).)

```apex
Query.setMock(new QueryMock(new List<SObject>()));

List<SObject> result = Query.records(null);
Assert.areEqual(0, result.size(), 'Mock returns the injected empty list.');
```

## Multiple Mock Responses

When the unit under test calls `Query.records(...)` more than once and each call
should return *different* records, use `QueryMock.Multiple`. It holds a queue of
response lists and hands them out in order, one per call.

### Queueing responses in order

`add(...)` is fluent (returns `this`), so you can chain. **The order you `add`
responses is the order they are returned** — the first `add` answers the first
`Query.records(...)` call, and so on.

```apex
List<SObject> firstBatch = new TestData(Account.sObjectType)
    .put(Account.Name, 'First')
    .build();
List<SObject> secondBatch = new TestData(Account.sObjectType)
    .put(Account.Name, 'Second')
    .count(3)
    .build();

Query.setMock(new QueryMock.Multiple()
    .add(firstBatch)
    .add(secondBatch));

List<SObject> call1 = Query.records(null);   // returns firstBatch
List<SObject> call2 = Query.records(null);   // returns secondBatch

Assert.areEqual('First', ((Account) call1[0]).Name, 'First call returns the first queued list.');
Assert.areEqual(3, call2.size(), 'Second call returns the second queued list.');
```

### Running out of responses is a failure

If the unit calls `Query.records(...)` more times than you queued, `Multiple`
throws `QueryMock.QueryMockException` rather than returning `null`. This is a
deliberate guardrail: an unexpected extra query usually means a bug, and you want
the test to surface it loudly.

```apex
Query.setMock(new QueryMock.Multiple().add(new List<SObject>{ new Account() }));

Query.records(null);   // ok: consumes the one queued response

try {
    Query.records(null);   // no responses left
    Assert.fail('Expected QueryMockException when responses are exhausted.');
} catch (QueryMock.QueryMockException e) {
    Assert.areEqual('No more records to return', e.getMessage(), 'Exhaustion is reported.');
}
```

> Match the number of `add(...)` calls to the number of `Query.records(...)` calls
> you expect. If you queue more than the unit consumes, the extras are simply
> never returned (no error); if you queue fewer, you get a `QueryMockException`.

## Gotchas & Testing Notes

- **The injected instance is static state.** `setMock` replaces a static field on
  `Query`. Salesforce resets static state between test methods, so each `@IsTest`
  method starts with the default (pass-through) `Query` — you do not need to reset
  it manually. But if one method sets a mock and a later assertion in the *same*
  method assumes default behavior, remember the mock is still active.

- **`setMock` is test-only.** It is `@TestVisible`, so production code cannot call
  it and cannot accidentally swap in a mock. Injection is strictly a testing
  concern.

- **The mock ignores its input.** Both `QueryMock.query` and
  `QueryMock.Multiple.query` discard the `List<SObject>` argument (it is even named
  `ignore`). The records returned are the ones you primed, not the ones the caller
  passed. Assert accordingly.

- **The default `QueryMock()` returns `null`.** Constructing `new QueryMock()`
  with no records leaves the internal list `null`, so `query(...)` returns `null`,
  not an empty list. For "no results," inject `new QueryMock(new List<SObject>())`
  instead.

- **`Multiple` is order-sensitive and exhaustible.** Responses come back in `add`
  order, and one extra `Query.records(...)` call past the queue throws
  `QueryMockException`. Keep the count of `add(...)` calls aligned with the number
  of queries the unit makes.

- **No defensive copying.** The default `Query` returns the exact list instance it
  was given, and `QueryMock` returns the exact list you supplied. Mutating the
  returned list mutates your source list. Build fresh records per test if that
  matters.

- **`Query` does not query.** It runs no SOQL or DML. It is purely an injection
  seam. If you need real querying — filters, ordering, relationships, bulk-safe
  chunking — that belongs in a selector or service layer, not here.

- **Cast at the point of use.** `records(...)` and the mocks return
  `List<SObject>`. Cast to the concrete type where you read the records so the seam
  itself stays generic.
