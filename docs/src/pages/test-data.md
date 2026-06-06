---
layout: ../layouts/DocsLayout.astro
title: TestData | sf-bedrock docs
description: Technical documentation and usage examples for the sf-bedrock TestData Apex utility.
eyebrow: Foundation API
heading: TestData
lede: A fluent builder that creates in-memory SObject records for Apex tests — including fields you normally cannot set, like formula fields, system audit fields, parent relationships, and Ids — without ever touching the database.
sections:
  - label: Purpose
    href: "#purpose"
  - label: How It Works
    href: "#how-it-works"
  - label: Public API
    href: "#public-api"
  - label: Examples
    href: "#examples"
  - label: Relationships
    href: "#relationships"
  - label: Read-Only & System Fields
    href: "#read-only-and-system-fields"
  - label: Mock Ids & IdService
    href: "#mock-ids-and-idservice"
  - label: Gotchas & Testing Notes
    href: "#gotchas-and-testing-notes"
---

## Purpose

`TestData` is a fluent builder for creating `SObject` records inside Apex unit
tests. You pick an object type, set the fields your assertions care about,
optionally generate mock Ids, and call `build()` — and you get back a
`List<SObject>` that lives entirely in memory.

The point is not just convenience. `TestData` can populate fields that the
standard `new Account(Name = 'x')` constructor **rejects** — formula fields,
rollup summaries, system audit fields (`CreatedDate`, `LastModifiedById`),
the `Id` field, and parent relationship objects. That makes it ideal for
testing code whose behavior depends on values your test cannot normally fake.

**Use `TestData` when** you want realistic records fast, with no DML, no SOQL,
and no governor-limit cost — typically to feed a service or unit under test.

**Reach for real DML instead when** the thing you are proving *is* database
behavior: validation rules, triggers, flows, sharing, rollups recalculated by
the platform, or anything that only happens on a real `insert`/`update`.

## How It Works

Three ideas explain everything `TestData` does.

### 1. It is a builder (fluent interface)

Every configuration method — `put`, `count`, `mockIds` — returns the same
`TestData` instance (`this`). That is what lets you chain calls in one
expression and read them top to bottom:

```apex
new TestData(Account.sObjectType)   // start a builder for Accounts
  .put(Account.Name, 'Bedrock')     // returns the same builder
  .count(3)                         // returns the same builder
  .mockIds()                        // returns the same builder
  .build();                         // ends the chain, returns records
```

Call order does not matter. `put`, `count`, and `mockIds` only record your
intent; nothing is created until `build()` runs.

### 2. It serializes through JSON to bypass field restrictions

Internally, `build()` assembles a plain `Map<String, Object>` for each record,
serializes the list to a JSON string, and deserializes it back into
`List<SObject>`:

```apex
List<SObject> results = (List<SObject>) JSON.deserialize(
  JSON.serialize(records),
  List<SObject>.class
);
```

This round-trip is the trick. Apex blocks you from assigning formula fields,
system fields, or `Id` through normal property setters, but **JSON
deserialization writes them anyway**. That is why `TestData` can build a record
that already "looks" inserted and audited even though no DML ever ran.

### 3. The records never touch the database

Everything happens in memory. No `insert`, no SOQL, no DML rows consumed, no
triggers fired. Tests stay fast and isolated. The flip side: these records are
for *mocking*, not for inserting — see
[Gotchas](#gotchas-and-testing-notes).

## Public API

`TestData` exposes a constructor, four fluent methods, and one inner helper
class.

> **A note on "properties":** `TestData` has no public properties. Its instance
> state — `sObjectType`, `template`, `count`, and `mockids` — is **private** and
> can only be changed through the methods below. This keeps the builder's state
> consistent and is why the fluent API is the only supported entry point.

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| Constructor | `TestData(SObjectType sObjectType)` | `TestData` | Starts a builder bound to one object type. Required first step. |
| `put` | `put(SObjectField field, Object value)` | `TestData` | Adds (or overwrites) a field/value pair in the record template. If `value` is an `SObject`, it is treated as a parent relationship — see [Relationships](#relationships). |
| `count` | `count(Integer count)` | `TestData` | Sets how many records `build()` returns. Defaults to `1`. |
| `mockIds` | `mockIds()` | `TestData` | Enables synthetic Id generation so every built record gets a unique, valid-looking `Id`. Off by default (Id is `null`). |
| `build` | `build()` | `List<SObject>` | Produces the records from the current template and returns them. Can be called more than once. |

### Private state behind the methods

Understanding the four private fields makes the behavior predictable:

| Field | Set by | Effect |
| --- | --- | --- |
| `sObjectType` | constructor | The object type every built record is deserialized into. |
| `template` | `put` | A `Map<SObjectField, Object>` of the field values applied to **every** record. |
| `count` | `count` | Number of records produced by `build()` (default `1`). |
| `mockids` | `mockIds` | When `true`, each record receives a generated `Id` (default `false`). |

### `IdService` (inner class)

`TestData` keeps one **static** `IdService` instance. Its single public method,
`get(SObjectType)`, returns the next sequential, valid 15-character Id for that
object type. You normally never call it directly — `mockIds()` uses it for you —
but it is public, so it is part of the surface. Details in
[Mock Ids & IdService](#mock-ids-and-idservice).

## Examples

### Create one typed record

By default `build()` returns a single record with an empty `Id`. `build()`
always returns a `List<SObject>`, so cast the element you need.

```apex
Account account = (Account) new TestData(Account.sObjectType)
  .put(Account.Name, 'Bedrock')
  .build()[0];

Assert.areEqual(
  'Bedrock',
  account.Name,
  'Expected TestData to populate the requested field.'
);
Assert.isNull(account.Id, 'Expected no Id without mockIds().');
```

### Build a focused list

Use `count(Integer)` when the behavior under test depends on list size.

```apex
List<Contact> contacts = (List<Contact>) new TestData(Contact.sObjectType)
  .put(Contact.LastName, 'Subscriber')
  .count(3)
  .build();

Assert.areEqual(
  3,
  contacts.size(),
  'Expected count(3) to build exactly three records.'
);
```

> Every record in a single `build()` shares the **same** template values. All
> three contacts above have `LastName = 'Subscriber'`. If you need records that
> differ from each other, build them in separate calls or set the differing
> fields after building.

### Set multiple fields

Chain `put` once per field. Calling `put` twice with the same field overwrites
the earlier value (the template is a map).

```apex
Opportunity opp = (Opportunity) new TestData(Opportunity.sObjectType)
  .put(Opportunity.Name, 'Renewal')
  .put(Opportunity.StageName, 'Prospecting')
  .put(Opportunity.Amount, 5000)
  .put(Opportunity.CloseDate, Date.today().addDays(30))
  .build()[0];

Assert.areEqual('Prospecting', opp.StageName, 'Expected staged opportunity.');
```

### Reuse a builder for variations

Because `build()` can be called repeatedly, you can configure a base builder
and produce snapshots as you adjust it. Each call returns a fresh list.

```apex
TestData builder = new TestData(Case.sObjectType)
  .put(Case.Subject, 'Login issue');

Case open = (Case) builder.put(Case.Status, 'New').build()[0];
Case closed = (Case) builder.put(Case.Status, 'Closed').build()[0];

Assert.areEqual('New', open.Status, 'Expected first snapshot to stay New.');
Assert.areEqual('Closed', closed.Status, 'Expected second snapshot to be Closed.');
```

### A realistic service test

The common shape: build mock records with Ids, hand them to the unit under
test, and assert on the result — no database involved.

```apex
@IsTest
static void categorizesHighValueAccounts() {
  List<Account> accounts = (List<Account>) new TestData(Account.sObjectType)
    .put(Account.Name, 'Enterprise Co')
    .put(Account.AnnualRevenue, 10000000)
    .mockIds()
    .count(2)
    .build();

  AccountTierService service = new AccountTierService();
  Map<Id, String> tiers = service.assignTiers(accounts);

  for (Account a : accounts) {
    Assert.areEqual('Enterprise', tiers.get(a.Id), 'Expected high revenue to map to Enterprise tier.');
  }
}
```

## Relationships

When the value you pass to `put` is itself an `SObject`, `TestData` treats it as
a **parent (lookup) relationship**. It does two things:

1. Copies the parent's `Id` onto the lookup field (e.g. `Contact.AccountId`).
2. Hydrates the relationship object so you can read parent fields through the
   dotted path (e.g. `contact.Account.Name`).

```apex
Account parent = (Account) new TestData(Account.sObjectType)
  .put(Account.Name, 'Parent Account')
  .mockIds()                          // parent needs an Id for the lookup to populate
  .build()[0];

Contact contact = (Contact) new TestData(Contact.sObjectType)
  .put(Contact.LastName, 'Child Contact')
  .put(Contact.AccountId, parent)     // pass the SObject, not parent.Id
  .mockIds()
  .build()[0];

Assert.areEqual(parent.Id, contact.AccountId, 'Expected the lookup Id to be copied.');
Assert.areEqual('Parent Account', contact.Account.Name, 'Expected the parent relationship to be hydrated.');
```

Things to remember:

- **Pass the record, not the Id.** Use `put(Contact.AccountId, parent)`, not
  `put(Contact.AccountId, parent.Id)`. Passing the Id only sets the lookup
  field; passing the record also gives you the dotted-path relationship.
- **Give the parent an Id first.** Call `mockIds()` on the parent builder.
  Without it the parent's `Id` is `null`, so the child's lookup field is `null`.
- **Parent direction only.** This handles lookups/master-detail *up* to a
  parent. Child relationship lists (e.g. `account.Contacts`) are not built this
  way, because child relationships are not `SObjectField`s.

## Read-Only & System Fields

This is where `TestData` earns its place. The JSON round-trip lets you set
fields the normal constructor refuses, which is invaluable when your code reads
formula fields, rollups, or audit data that a test cannot otherwise produce.

```apex
// Suppose code under test branches on a formula field and on CreatedDate.
Account aged = (Account) new TestData(Account.sObjectType)
  .put(Account.Name, 'Legacy Account')
  .put(Account.CreatedDate, Datetime.now().addYears(-3))  // system field
  .build()[0];

Assert.isTrue(
  aged.CreatedDate < Datetime.now().addYears(-1),
  'Expected to backdate a normally read-only system field.'
);
```

The same approach works for formula and rollup-summary fields. You are
asserting against records that *look* like the platform produced them, without
needing the platform to produce them.

> **Important:** these values exist only on the in-memory record. They are
> perfect for feeding a unit under test, but if you ever `insert` a record with
> read-only fields populated, the DML will fail — read-only means read-only to
> the database. Keep `TestData` records on the mocking side of your tests.

## Mock Ids & IdService

Calling `mockIds()` makes `build()` assign a generated `Id` to every record.
Each Id is:

- **Valid-looking** — it begins with the object's real 3-character key prefix
  (`001` for Account, `003` for Contact, etc.), so it deserializes into a real
  `Id` value.
- **Sequential and unique** — the `IdService` keeps a per-object counter and
  zero-pads it to a 15-character Id, e.g. `001000000000001`,
  `001000000000002`, …
- **Distinct per record** — even within one `build()`, every record gets the
  next number, so a list of mock records never shares an Id.

```apex
List<Account> accounts = (List<Account>) new TestData(Account.sObjectType)
  .put(Account.Name, 'Mocked')
  .mockIds()
  .count(2)
  .build();

Assert.areNotEqual(
  accounts[0].Id,
  accounts[1].Id,
  'Expected each generated mock Id to be unique.'
);
```

### The counter is static (transaction-wide)

`TestData` shares **one static** `IdService` across every builder in the
transaction. The counter keeps climbing — it does not reset between builders or
between `build()` calls. So if you build 2 Accounts and then build 3 more, the
second batch continues from where the first left off.

The practical consequence: **assert on uniqueness or key prefix, never on a
hard-coded Id string.** The exact number depends on how many records were built
earlier in the same test, which makes literal Id assertions brittle.

```apex
Account a = (Account) new TestData(Account.sObjectType).mockIds().build()[0];

// Good: stable property of the Id
Assert.isTrue(((String) a.Id).startsWith('001'), 'Expected an Account key prefix.');

// Avoid: depends on prior builds in the transaction
// Assert.areEqual('001000000000001', a.Id, ...);
```

## Gotchas & Testing Notes

- **No Id unless you ask.** Without `mockIds()`, `Id` is `null`. Code that keys
  records by `Id` (maps, dedupe logic) needs `mockIds()`.
- **Records in one `build()` are identical** except for their generated Ids.
  Build separately when you need different field values per record.
- **Mock Ids are not stable across the transaction.** Assert on uniqueness or
  key prefix, not on a specific Id string (see above).
- **These records are for mocking, not DML.** Inserting a record with read-only
  or system fields populated will fail. Use real DML only when the database
  behavior itself is the thing under test.
- **Set only the fields your assertions need.** Focused records keep tests
  readable and resilient to unrelated schema changes.
- **Cast close to usage.** `build()` returns `List<SObject>`; cast to the
  concrete type at the point you read it so setup stays generic and concise.
