---
layout: ../layouts/DocsLayout.astro
title: DML | sf-bedrock docs
description: Technical documentation and usage examples for the sf-bedrock DML Apex facade and its DMLMock test double.
eyebrow: Dependency Injection
heading: DML
lede: A static facade over Apex DML operations that routes every insert, update, upsert, delete, and undelete through one swappable instance — so production code runs real DML, and tests swap in DMLMock to capture every operation without ever touching the database.
sections:
  - label: Purpose
    href: "#purpose"
  - label: How It Works
    href: "#how-it-works"
  - label: Public API
    href: "#public-api"
  - label: Examples
    href: "#examples"
  - label: Testing With DMLMock
    href: "#testing-with-dmlmock"
  - label: Gotchas & Testing Notes
    href: "#gotchas-and-testing-notes"
---

## Purpose

`DML` is a thin static facade over the six Apex DML verbs: `insert`, `update`,
`upsert` (with and without an external Id), `delete`, and `undelete`. Instead of
writing `insert records;` directly in your service classes, you call
`DML.insertRecords(records)` and the work is delegated to a single, swappable
instance behind the scenes.

The point is **testability through dependency injection**. Because every DML
operation flows through one replaceable object, a test can substitute a mock
(`DMLMock`) that records what *would* have been written — and asserts on it —
without consuming DML rows, firing triggers, or hitting the database at all.

**Use `DML` when** your business logic performs DML and you want to unit-test
that logic in isolation: prove that a service inserts the right records, updates
the right ones, deletes nothing it shouldn't, and so on, all in memory.

**Reach for raw DML (`insert records;`) or `Database` methods instead when** the
database behavior itself is the thing under test — triggers, flows, validation
rules, sharing recalculation, partial-success handling, or anything that only a
real commit produces. `DML` deliberately does not expose `Database.DMLOptions`,
`allOrNone` flags, or `Database.SaveResult[]`; if you need those, call the
platform directly.

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

The default `instance` is a plain `Service`, whose methods run **real** DML
(`insert records;`, `update records;`, etc.). So in production, calling
`DML.insertRecords(...)` is functionally identical to writing the DML yourself —
just routed through one place.

### 2. The instance is swappable (the seam for mocking)

The static `instance` can be replaced through `setMock(Service)`:

```apex
@testvisible static void setMock(Service mock) {
    instance = mock;
}
```

`setMock` is annotated `@TestVisible`, so it is callable **only from test
context** — production code cannot accidentally swap the delegate. Swap in a
subclass of `Service` and every subsequent `DML.*` call is intercepted. This is
the classic dependency-injection seam: production wires up the real
implementation, tests wire up a fake.

### 3. The `Contract` interface defines the surface both sides honor

The inner `Contract` interface lists the six operations. `Service` (the real
implementation) `implements Contract`, and `DMLMock extends DML.Service` so it
inherits the same shape and overrides each method. Both the real and the mock
implementations therefore expose an identical API, which is what makes them
interchangeable.

> **A note on the class header.** `DML` is declared `public virtual inherited
> sharing class DML extends Service` — it extends its own inner `Service` class.
> That detail is incidental to using the facade: you call the **static** methods
> on `DML`, not instances of it. Every operation runs in the sharing context of
> the calling code (`inherited sharing`).

## Public API

`DML` exposes six static methods (the DML verbs) and nothing else that
production code should call. `setMock` exists but is test-only.

> **A note on "properties":** `DML` has no public properties. Its only state is
> the `static Service instance`, which is **private** (no access modifier in
> Apex means private) and can be changed only through `setMock`. There is no
> public getter or setter, by design — the instance is an implementation detail
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
running DML, it **records** the records it was handed. Its captured-call lists
are public:

| Member | Type | Description |
| --- | --- | --- |
| `inserts` | `List<List<SObject>>` | One entry per `insertRecords` call, holding that call's records. |
| `updates` | `List<List<SObject>>` | One entry per `updateRecords` call. |
| `upserts` | `List<List<SObject>>` | One entry per upsert call. **Both** `upsertRecords` overloads append here; the external-Id field itself is not captured. |
| `deletes` | `List<List<SObject>>` | One entry per `deleteRecords` call. |
| `undeletes` | `List<List<SObject>>` | One entry per `undeleteRecords` call. |

Each list is a list **of calls**, and each call is the list of records passed to
it. So `dmlMock.inserts.size()` is the number of insert *calls*, and
`dmlMock.inserts[0].size()` is the number of records in the first insert call.

## Examples

### Production code: write DML through the facade

In service or domain code, replace bare DML statements with facade calls. The
behavior is identical at runtime, but the call is now interceptable in tests.

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

### Upsert with an external Id

The second `upsertRecords` overload takes an `SObjectField` to match on,
delegating to `Database.upsert(records, externalIdField, true)` — note the
`true`, which means **all-or-none**: if any row fails, the whole operation rolls
back and throws.

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

## Testing With DMLMock

This is where `DML` pays off. The pattern is: build in-memory records (the
sf-bedrock [`TestData`](./test-data) builder pairs naturally with this), inject
a `DMLMock`, call the code under test, then assert on what the mock captured.

### The setup helper

`DMLTest` uses a tiny helper that constructs the mock, installs it via
`setMock`, and returns it so the test can assert against it:

```apex
static DMLMock setupDmlMock() {
    DMLMock dmlMock = new DMLMock();
    DML.setMock(dmlMock);
    return dmlMock;
}
```

After `setupDmlMock()` runs, every `DML.*` call in that test is routed to the
mock instead of the database. Copy this helper into your own test class (or a
shared test utility) and you have a one-line way to neutralize DML.

### Asserting an insert

Build records, run the operation, and check the capture lists. Note the two
levels: number of calls, then records per call.

```apex
@IsTest
static void testInsertRecords() {
    DMLMock dmlMock = setupDmlMock();
    List<SObject> records = new TestData(Account.sObjectType)
        .put(Account.Name, 'Bedrock Insert')
        .count(2)
        .build();

    DML.insertRecords(records);

    // Exactly one insert call was captured...
    Assert.areEqual(1, dmlMock.inserts.size(),
        'Expected exactly one insert call to be captured by DMLMock.');
    // ...containing both records...
    Assert.areEqual(2, dmlMock.inserts[0].size(),
        'Expected insert call to contain both provided records.');
    // ...and the payload was preserved.
    Assert.areEqual('Bedrock Insert', ((Account) dmlMock.inserts[0][0]).Name,
        'Expected inserted account name to be preserved in the captured payload.');
}
```

### Proving the *other* operations did not fire

A powerful, often-overlooked assertion: confirm your code took the path you
expect and nothing else. Every `DMLTest` method asserts the unrelated capture
lists are empty.

```apex
@IsTest
static void testUpdateRecords() {
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

    // The update path must not touch any other verb.
    Assert.areEqual(0, dmlMock.inserts.size(), 'Expected update path to avoid insert calls.');
    Assert.areEqual(0, dmlMock.upserts.size(), 'Expected update path to avoid upsert calls.');
    Assert.areEqual(0, dmlMock.deletes.size(), 'Expected update path to avoid delete calls.');
    Assert.areEqual(0, dmlMock.undeletes.size(), 'Expected update path to avoid undelete calls.');
}
```

### Both upsert overloads land in `upserts`

`DMLMock` records the plain upsert and the external-Id upsert in the **same**
`upserts` list. The external-Id field passed to the second overload is *not*
captured — only the records are.

```apex
@IsTest
static void testUpsertRecordsWithExternalId() {
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
> *which* field was used for matching. If matching field is critical to your
> logic, assert on the records' field values (as above) rather than on the mock.

### Delete and undelete

`delete` and `undelete` are mocked the same way — they require records with Ids,
so use `mockIds()` when building them.

```apex
@IsTest
static void testDeleteRecords() {
    DMLMock dmlMock = setupDmlMock();
    List<SObject> records = new TestData(Account.sObjectType)
        .put(Account.Name, 'Bedrock Delete')
        .mockIds()
        .count(2)
        .build();

    DML.deleteRecords(records);

    Assert.areEqual(1, dmlMock.deletes.size(),
        'Expected exactly one delete call to be captured by DMLMock.');
    Assert.areEqual(2, dmlMock.deletes[0].size(),
        'Expected delete call to contain both provided records.');
}
```

### Testing your own service

The realistic shape: inject the mock, call your service, assert it performed the
expected DML — all without a single SOQL query or DML row consumed.

```apex
@IsTest
static void onboardInsertsCustomers() {
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

### Custom delegates beyond `DMLMock`

`setMock` accepts any `DML.Service` subclass, not just `DMLMock`. Because every
`Service` method is `virtual`, you can build a delegate that simulates failure —
useful for testing error handling.

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

## Gotchas & Testing Notes

- **No access modifier means private.** The `instance` field has no modifier, so
  it is private. Production code has no way to read or replace the delegate —
  only `@TestVisible setMock` can, and only in test context. That is
  intentional: the facade's plumbing is sealed.

- **`setMock` is `@TestVisible`, not `public`.** You cannot call it from
  production code. It is the only way to swap the delegate, and it works solely
  inside tests.

- **The delegate is static — install it before the code under test runs.** A
  `setMock` call replaces the static `instance` for the remainder of the test
  transaction. Call it in your `@IsTest` method (or a `@TestSetup`-style helper)
  *before* invoking the code that performs DML, or the real DML will run.

- **Both upsert overloads share the `upserts` list, and the external-Id field is
  not captured.** Assert on record field values, not on the matching field, when
  using the external-Id overload.

- **The mock captures *references*, not snapshots.** `DMLMock` stores the same
  `List<SObject>` you passed in. If the code under test (or your test) mutates
  those records *after* the call, the captured list reflects the mutation. To
  assert on the state at call time, assert immediately after the call.

- **`DMLMock` assigns no Ids.** Real `insert`/`upsert` populate `Id` on success;
  the mock does not. If your code reads `record.Id` after a `DML.insert`, give
  the records Ids up front with `TestData.mockIds()`, since the mock will not
  fill them in.

- **The external-Id upsert is all-or-none.** In production it calls
  `Database.upsert(records, externalIdField, true)`. The `true` means a single
  failed row rolls back the whole batch and throws — there is no partial-success
  result to inspect. If you need partial success, call `Database.upsert`
  yourself; the facade does not expose that option.

- **`void` return, no results to inspect.** None of the facade methods return
  `Database.SaveResult[]`. Errors surface as thrown `DmlException`s, just like
  raw DML statements. To verify behavior, assert on the `DMLMock` capture lists
  (in tests) or on the records' downstream effects.

- **The facade adds no batching or governor protection.** It is a pass-through:
  `DML.insertRecords` consumes one DML statement against governor limits exactly
  as a bare `insert` would. Bulkify by passing whole lists, not by calling the
  facade in a loop.
