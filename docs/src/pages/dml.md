---
layout: ../layouts/DocsLayout.astro
title: DML | sf-bedrock docs
description: Write normal Apex DML through a tiny API so tests can capture intended database changes without committing records.
eyebrow: Dependency Injection
heading: DML
lede: DML lets production code commit records normally while tests capture the intended inserts, updates, upserts, deletes, and undeletes in memory.
sections:
  - label: Overview
    href: "#overview"
  - label: Quickstart
    href: "#quickstart"
  - label: Examples
    href: "#examples"
  - label: Testing
    href: "#testing"
  - label: How It Works
    href: "#how-it-works"
  - label: Public API
    href: "#public-api"
  - label: Notes & Edge Cases
    href: "#notes--edge-cases"
---

## Overview

`DML` wraps the six Apex DML verbs: `insert`, `update`, `upsert` (with and
without an external Id), `delete`, and `undelete`. Instead of writing
`insert records;` directly in your service classes, call
`DML.insertRecords(records)`. Production still commits records. Tests can swap in
`DMLMock` and inspect what would have happened.

**Use `DML` when** your business logic performs DML and you want to unit-test
that logic in isolation — prove that a service inserts the right records, updates
the right ones, and deletes nothing it shouldn't, all in memory.

**Reach for raw DML (`insert records;`) or `Database` methods instead when** the
database behavior itself is the thing under test: triggers, flows, validation
rules, sharing recalculation, partial-success handling, or anything that only a
real commit produces. `DML` deliberately does not expose `Database.DMLOptions`,
`allOrNone` flags, or `Database.SaveResult[]`. If you need those, call the
platform directly.

## Quickstart

Replace bare DML statements with `DML` calls. The runtime behavior is identical,
and your service now produces testable writes without any other change.

```apex
public class AccountService {
    public void onboard(List<Account> accounts) {
        for (Account a : accounts) {
            a.Type = 'Customer';
        }
        DML.insertRecords(accounts);   // instead of: insert accounts;
    }
}
```

## Examples

### Upsert with an external Id

The second `upsertRecords` overload takes an `SObjectField` to match on,
delegating to `Database.upsert(records, externalIdField, true)` — the `true`
means **all-or-none**: if any row fails, the whole operation rolls back and throws.

```apex
List<Contact> contacts = loadFromIntegration();
DML.upsertRecords(contacts, Contact.Email);   // match existing rows by Email
```

### Mixing operations

Each verb maps one-to-one to its Apex statement, so you can compose them as you
would normally:

```apex
DML.insertRecords(newRecords);
DML.updateRecords(changedRecords);
DML.deleteRecords(staleRecords);
```

### Testing your own service

The realistic shape: inject `DMLMock`, call your service, assert it performed the
expected DML — all without a single SOQL query or DML row consumed.

```apex
@istest static void onboardInsertsCustomers() {
    DMLMock dmlMock = new DMLMock();
    DML.setMock(dmlMock);

    List<Account> accounts = (List<Account>) new TestData(Account.sObjectType)
        .put(Account.Name, 'Prospect Co')
        .count(2)
        .build();

    new AccountService().onboard(accounts);

    Assert.areEqual(1, dmlMock.inserts.size(),
        'Expected onboard() to perform exactly one insert.');
    Assert.areEqual('Customer', ((Account) dmlMock.inserts[0][0]).Type,
        'Expected onboard() to stamp Type before inserting.');
    Assert.areEqual(0, dmlMock.updates.size(),
        'Expected onboard() not to update anything.');
}
```

## Testing

`DMLMock` is the test double for `DML`. It extends `DML.Service` and overrides
every method so that, instead of running DML, it records the records it was
handed. Install it once with `DML.setMock(dmlMock)` and every subsequent
`DML.*` call in that test is routed to the mock.

### The setup helper

A small helper constructs the mock, installs it, and returns it so the test can
assert against it:

```apex
static DMLMock setupDmlMock() {
    DMLMock dmlMock = new DMLMock();
    DML.setMock(dmlMock);
    return dmlMock;
}
```

### Asserting on captured calls

`DMLMock` stores one entry per call, and each entry is the list of records that
was passed in. So `dmlMock.inserts.size()` is the number of insert *calls*, and
`dmlMock.inserts[0].size()` is the number of records in the first call.

```apex
@istest static void testInsertRecords() {
    DMLMock dmlMock = setupDmlMock();
    List<SObject> records = new TestData(Account.sObjectType)
        .put(Account.Name, 'Bedrock Insert')
        .count(2)
        .build();

    DML.insertRecords(records);

    Assert.areEqual(1, dmlMock.inserts.size(),
        'Expected exactly one insert call to be captured by DMLMock.');
    Assert.areEqual(2, dmlMock.inserts[0].size(),
        'Expected insert call to contain both provided records.');
    Assert.areEqual('Bedrock Insert', ((Account) dmlMock.inserts[0][0]).Name,
        'Expected inserted account name to be preserved in the captured payload.');
}
```

### Proving other operations did not fire

Assert that the capture lists for other verbs are empty. This confirms your code
took the path you expect and nothing else.

```apex
@istest static void testUpdateRecords() {
    DMLMock dmlMock = setupDmlMock();
    List<SObject> records = new TestData(Account.sObjectType)
        .put(Account.Name, 'Bedrock Update')
        .mockIds()             // update needs Ids on the records
        .count(2)
        .build();

    DML.updateRecords(records);

    Assert.areEqual(1, dmlMock.updates.size(),
        'Expected exactly one update call to be captured by DMLMock.');
    Assert.areEqual('Bedrock Update', ((Account) dmlMock.updates[0][1]).Name,
        'Expected updated account name to be preserved in the captured payload.');

    Assert.areEqual(0, dmlMock.inserts.size(), 'Expected update path to avoid insert calls.');
    Assert.areEqual(0, dmlMock.upserts.size(), 'Expected update path to avoid upsert calls.');
    Assert.areEqual(0, dmlMock.deletes.size(), 'Expected update path to avoid delete calls.');
    Assert.areEqual(0, dmlMock.undeletes.size(), 'Expected update path to avoid undelete calls.');
}
```

### Both upsert overloads land in `upserts`

`DMLMock` records the plain upsert and the external-Id upsert in the same
`upserts` list. The external-Id field passed to the second overload is not
captured — only the records are.

```apex
@istest static void testUpsertRecordsWithExternalId() {
    DMLMock dmlMock = setupDmlMock();
    List<SObject> records = new TestData(Contact.sObjectType)
        .put(Contact.LastName, 'External')
        .put(Contact.Email, 'external@example.com')
        .count(2)
        .build();

    DML.upsertRecords(records, Contact.Email);

    Assert.areEqual(1, dmlMock.upserts.size(),
        'Expected exactly one external-id upsert call to be captured by DMLMock.');
    Assert.areEqual('external@example.com', ((Contact) dmlMock.upserts[0][0]).Email,
        'Expected external-id field value to be preserved in the captured payload.');
}
```

> Because the external-Id field is discarded by the mock, you cannot assert on
> which field was used for matching. Assert on the records' field values instead.

### Custom delegates beyond `DMLMock`

`setMock` accepts any `DML.Service` subclass. Because every `Service` method is
`virtual`, you can build a delegate that simulates failure — useful for testing
error handling in your catch blocks.

```apex
public class FailingDml extends DML.Service {
    public override void insertRecords(List<SObject> records) {
        throw new DmlException('Simulated insert failure');
    }
}

// In a test:
DML.setMock(new FailingDml());
// Now DML.insertRecords(...) throws, exercising your catch block.
```

## How It Works

Three ideas explain everything `DML` does.

### 1. It is a facade backed by a single instance (dependency injection)

`DML` holds one **static** `Service` instance and forwards every public static
method to it:

```apex
public virtual inherited sharing class DML extends Service {
    static Service instance = new Service();   // the live delegate

    public static void insertRecords(List<SObject> records) {
        instance.insertRecords(records);       // forward to the instance
    }
    // ... the other five verbs forward the same way
}
```

The default `instance` is a plain `Service`, whose methods run real DML
(`insert records;`, `update records;`, etc.). In production, calling
`DML.insertRecords(...)` is functionally identical to writing the DML yourself —
just routed through one place.

### 2. The instance is swappable (the seam for mocking)

The static `instance` can be replaced through `setMock(Service)`:

```apex
@testvisible static void setMock(Service mock) {
    instance = mock;
}
```

`setMock` is annotated `@TestVisible`, so it is callable only from test
context — production code cannot accidentally swap the delegate. Swap in a
subclass of `Service` and every subsequent `DML.*` call is intercepted.

### 3. The `Contract` interface defines the surface both sides honor

The inner `Contract` interface lists the six operations. `Service` (the real
implementation) `implements Contract`. `DMLMock extends DML.Service`, so it
inherits the same shape and overrides each method. Both the real and the mock
implementations expose an identical API — that's what makes them interchangeable.

> `DML` is declared `public virtual inherited sharing class DML extends Service` —
> it extends its own inner `Service` class. That detail is incidental to using
> the facade. You call the **static** methods on `DML`, not instances of it.
> Every operation runs in the sharing context of the calling code
> (`inherited sharing`).

## Public API

`DML` exposes six static methods (the DML verbs) and nothing else that
production code should call. `setMock` exists but is test-only.

> **A note on "properties":** `DML` has no public properties. Its only state is
> the `static Service instance`, which is **private** — no access modifier in
> Apex means private. It can be changed only through `setMock`. There is no
> public getter or setter, by design. The instance is an implementation detail
> of the facade.

### Static methods (the facade)

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| `insertRecords` | `insertRecords(List<SObject> records)` | `void` | Inserts the records. In production runs `insert records;`. |
| `updateRecords` | `updateRecords(List<SObject> records)` | `void` | Updates the records. In production runs `update records;`. |
| `upsertRecords` | `upsertRecords(List<SObject> records)` | `void` | Upserts the records by Id. In production runs `upsert records;`. |
| `upsertRecords` | `upsertRecords(List<SObject> records, SObjectField externalIdField)` | `void` | Upserts using an external-Id field. In production runs `Database.upsert(records, externalIdField, true)` (all-or-none). |
| `deleteRecords` | `deleteRecords(List<SObject> records)` | `void` | Deletes the records. In production runs `delete records;`. |
| `undeleteRecords` | `undeleteRecords(List<SObject> records)` | `void` | Undeletes (recovers from the Recycle Bin) the records. In production runs `undelete records;`. |

Every method returns `void`. None of them surfaces `Database.SaveResult[]` or
similar — they either succeed or throw a `DmlException`, exactly like the
underlying DML statements.

### Test-only method

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| `setMock` | `setMock(DML.Service mock)` | `void` | `@TestVisible`. Replaces the static delegate for the rest of the test transaction. Pass a `DMLMock` (or any `DML.Service` subclass) to intercept DML. |

### Inner types

| Type | Kind | Description |
| --- | --- | --- |
| `DML.Service` | `public virtual inherited sharing class` | The default delegate. Each method runs the real DML statement. All six methods are `virtual`, so subclasses (like `DMLMock`) can override them. Extend this to build a custom delegate. |
| `DML.Contract` | `public interface` | Declares the six operations. Implemented by `Service`; the formal description of the facade's surface. |

### `DMLMock` (test double)

`DMLMock extends DML.Service` and overrides every method so that, instead of
running DML, it records the records it was handed. Its captured-call lists
are public:

| Member | Type | Description |
| --- | --- | --- |
| `inserts` | `List<List<SObject>>` | One entry per `insertRecords` call, holding that call's records. |
| `updates` | `List<List<SObject>>` | One entry per `updateRecords` call. |
| `upserts` | `List<List<SObject>>` | One entry per upsert call. **Both** `upsertRecords` overloads append here; the external-Id field itself is not captured. |
| `deletes` | `List<List<SObject>>` | One entry per `deleteRecords` call. |
| `undeletes` | `List<List<SObject>>` | One entry per `undeleteRecords` call. |

Each list is a list of calls, and each call is the list of records passed to
it. So `dmlMock.inserts.size()` is the number of insert calls, and
`dmlMock.inserts[0].size()` is the number of records in the first insert call.

## Notes & Edge Cases

- **No access modifier means private.** The `instance` field has no modifier, so
  it is private. Production code has no way to read or replace the delegate —
  only `@TestVisible setMock` can, and only in test context.

- **`setMock` is `@TestVisible`, not `public`.** You cannot call it from
  production code. It is the only way to swap the delegate, and it works solely
  inside tests.

- **The delegate is static — install it before the code under test runs.** A
  `setMock` call replaces the static `instance` for the remainder of the test
  transaction. Call it before invoking the code that performs DML. If you don't,
  the real DML will run.

- **Both upsert overloads share the `upserts` list, and the external-Id field is
  not captured.** When using the external-Id overload, assert on record field
  values — not on the matching field itself.

- **The mock captures references, not snapshots.** `DMLMock` stores the same
  `List<SObject>` you passed in. If your code (or the test itself) mutates those
  records after the call, the captured list reflects that mutation. Assert
  immediately after the call to see the state at call time.

- **`DMLMock` assigns no Ids.** Real `insert`/`upsert` populate `Id` on success.
  The mock does not. If your code reads `record.Id` after a `DML.insertRecords`
  call, give the records Ids up front with `TestData.mockIds()`.

- **The external-Id upsert is all-or-none.** In production it calls
  `Database.upsert(records, externalIdField, true)`. A single failed row rolls
  back the whole batch and throws. There is no partial-success result to inspect.
  If you need partial success, call `Database.upsert` yourself — the facade does
  not expose that option.

- **`void` return, no results to inspect.** None of the facade methods return
  `Database.SaveResult[]`. Errors surface as thrown `DmlException`s — just like
  raw DML statements. In tests, verify behavior by asserting on the `DMLMock`
  capture lists. In production flows, check the records' downstream effects.

- **The facade adds no batching or governor protection.** It is a pass-through.
  `DML.insertRecords` consumes one DML statement against governor limits, exactly
  as a bare `insert` would. Bulkify by passing whole lists — not by calling the
  facade in a loop.
