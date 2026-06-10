---
layout: ../layouts/DocsLayout.astro
title: TestData | sf-bedrock docs
description: A fluent builder that creates in-memory SObject records for Apex unit tests — including writting fields that are normally read-only — without touching the database.
eyebrow: Foundation API
heading: TestData
lede: A fluent builder that creates in-memory SObject records for Apex tests — including writting fields you normally cannot set, like formula fields, system audit fields, parent relationships, and Ids — without ever touching the database.
sections:
  - label: Overview
    href: "#overview"
  - label: Quickstart
    href: "#quickstart"
  - label: Examples
    href: "#examples"
  - label: Relationships
    href: "#relationships"
  - label: Read-Only & System Fields
    href: "#read-only-and-system-fields"
  - label: Mock Ids
    href: "#mock-ids"
  - label: How It Works
    href: "#how-it-works"
  - label: Public API
    href: "#public-api"
  - label: Notes & Edge Cases
    href: "#notes-and-edge-cases"
---

## Overview

`TestData` is a fluent builder for creating `SObject` records inside Apex unit
tests. You pick an object type, set the fields your assertions care about,
optionally generate mock Ids, and call `build()`. You get back a
`List<SObject>` that lives entirely in memory.

The point is not just convenience. `TestData` can populate fields that the
standard `new Account(Name = 'x')` constructor **rejects**: formula fields,
rollup summaries, system audit fields (`CreatedDate`, `LastModifiedById`),
the `Id` field, and parent relationship objects. That makes it ideal for
testing code whose behavior depends on values your test cannot otherwise fake.

**Use `TestData` when** you want realistic records fast — no DML, no SOQL, no
governor-limit cost — typically to feed a service or unit under test.

**Reach for real DML instead when** the thing you are proving *is* database
behavior: validation rules, triggers, flows, sharing, rollups recalculated by
the platform, or anything that only happens on a real `insert`/`update`.

## Quickstart

The smallest "make a record" moment: one object type, one field, one typed
record.

```apex
Account account = (Account) new TestData(Account.sObjectType)
    .put(Account.Name, 'Bedrock')
    .build()[0];
```

When the code under test needs an `Id` — for maps, lookups, or anything that
keys records — add `mockIds()` before `build()`.

```apex
Account account = (Account) new TestData(Account.sObjectType)
    .put(Account.Name, 'Bedrock')
    .mockIds()
    .build()[0];
```

That is the full contract. Everything else is a variation on this chain.

## Examples

### Create one typed record

`build()` always returns a `List<SObject>`. Cast the element you need at the
point of use.

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

### Build a list

Use `count(Integer)` when the behavior under test depends on list size. Every
record in a single `build()` call shares the same template values.

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

> All three contacts above have `LastName = 'Subscriber'`. If you need records
> with different field values, build them in separate calls or mutate the fields
> after building.

### Set multiple fields

Chain `put` once per field. Calling `put` twice with the same field overwrites
the earlier value — the template is a map.

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

`build()` can be called more than once on the same instance. Each call
produces a fresh list from the current template state.

```apex
TestData builder = new TestData(Case.sObjectType)
    .put(Case.Subject, 'Login issue');

Case open   = (Case) builder.put(Case.Status, 'New').build()[0];
Case closed = (Case) builder.put(Case.Status, 'Closed').build()[0];

Assert.areEqual('New',    open.Status,   'Expected first snapshot to stay New.');
Assert.areEqual('Closed', closed.Status, 'Expected second snapshot to be Closed.');
```

### Realistic service test

`TestData` is itself a test utility with no separate mock, so this realistic
service test serves as the "Testing" section of the spine. The common shape:
build mock records with Ids, hand them to the unit under test, and assert on
the result — no database involved.

```apex
@istest
static void testAssignTiers_highRevenueMapToEnterprise() {
    List<Account> accounts = (List<Account>) new TestData(Account.sObjectType)
        .put(Account.Name, 'Enterprise Co')
        .put(Account.AnnualRevenue, 10000000)
        .mockIds()
        .count(2)
        .build();

    AccountTierService service = new AccountTierService();
    Map<Id, String> tiers = service.assignTiers(accounts);

    for (Account a : accounts) {
        Assert.areEqual(
            'Enterprise',
            tiers.get(a.Id),
            'Expected high revenue to map to Enterprise tier.'
        );
    }
}
```

## Relationships

When the value you pass to `put` is itself an `SObject`, `TestData` treats it
as a **parent (lookup) relationship**. It does two things:

1. Copies the parent's `Id` onto the lookup field (e.g. `Contact.AccountId`).
2. Hydrates the relationship object so you can traverse the dotted path
   (e.g. `contact.Account.Name`).

```apex
Account parent = (Account) new TestData(Account.sObjectType)
    .put(Account.Name, 'Parent Account')
    .mockIds()
    .build()[0];

Contact contact = (Contact) new TestData(Contact.sObjectType)
    .put(Contact.LastName, 'Child Contact')
    .put(Contact.AccountId, parent)   // pass the SObject, not parent.Id
    .mockIds()
    .build()[0];

Assert.areEqual(parent.Id,          contact.AccountId,       'Expected the lookup Id to be copied.');
Assert.areEqual('Parent Account',   contact.Account.Name,    'Expected the parent relationship to be hydrated.');
```

Things to remember:

- **Pass the record, not the Id.** Use `put(Contact.AccountId, parent)`, not
  `put(Contact.AccountId, parent.Id)`. Passing the Id only sets the lookup
  field; passing the record also hydrates the dotted-path relationship.
- **Give the parent an Id first.** Call `mockIds()` on the parent builder.
  Without it the parent's `Id` is `null`, so the child's lookup field is `null`.
- **Parent direction only.** This handles lookups and master-detail *up* to a
  parent. Child relationship lists (e.g. `account.Contacts`) are not built this
  way because child relationships are not `SObjectField`s.

## Read-Only & System Fields

This is where `TestData` earns its place. The JSON round-trip lets you set
fields the normal constructor refuses. That matters when your code reads
formula fields, rollups, or audit data that a test cannot otherwise produce.

```apex
Account aged = (Account) new TestData(Account.sObjectType)
    .put(Account.Name, 'Legacy Account')
    .put(Account.CreatedDate, Datetime.now().addYears(-3))
    .build()[0];

Assert.isTrue(
    aged.CreatedDate < Datetime.now().addYears(-1),
    'Expected to backdate a normally read-only system field.'
);
```

The same approach works for formula and rollup-summary fields. The record
*looks* like the platform produced it without needing the platform to produce
it.

> **Important:** these values exist only on the in-memory record. If you ever
> `insert` a `TestData` record that has read-only fields populated, the DML
> will fail. Those fields are still read-only to the database. Keep `TestData`
> records on the mocking side of your tests.

## Mock Ids

Calling `mockIds()` makes `build()` assign a generated `Id` to every record.
Each Id is:

- **Valid-looking** — it starts with the object's real 3-character key prefix
  (`001` for Account, `003` for Contact, etc.), so it deserializes into a real
  `Id` value.
- **Sequential and unique** — `IdService` keeps a per-object-type counter and
  zero-pads it to a 15-character Id (e.g. `001000000000001`,
  `001000000000002`, …).
- **Distinct per record** — within a single `build()`, every record receives the
  next counter value, so a list of mock records never shares an Id.

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

### The counter is static and transaction-wide

`TestData` keeps **one static** `IdService` instance shared across every builder
in the transaction. Each object type has its own counter inside that instance,
and no counter resets between builders or between `build()` calls. Build 2
Accounts, then build 3 more — the second batch continues from 3, not 1.

The practical consequence: **assert on uniqueness or key prefix, not on a
hard-coded Id string.** The exact counter value depends on how many records of
that type were built earlier in the same test run.

```apex
Account a = (Account) new TestData(Account.sObjectType)
    .mockIds()
    .build()[0];

// Good: a stable property of the Id
Assert.isTrue(
    ((String) a.Id).startsWith('001'),
    'Expected an Account key prefix.'
);

// Avoid: depends on prior builds in the transaction
// Assert.areEqual('001000000000001', a.Id, ...);
```

## How It Works

Three ideas explain everything `TestData` does.

### 1. It is a fluent builder

Every configuration method — `put`, `count`, `mockIds` — returns the same
`TestData` instance (`this`). That is what lets you chain calls in one
expression:

```apex
new TestData(Account.sObjectType)
    .put(Account.Name, 'Bedrock')
    .count(3)
    .mockIds()
    .build();
```

Call order among `put`, `count`, and `mockIds` does not matter. They only
record intent; nothing is created until `build()` runs.

### 2. It serializes through JSON to bypass field restrictions

Internally, `build()` assembles a `Map<String, Object>` for each record,
serializes the list to a JSON string, and deserializes it back into
`List<SObject>`:

```apex
List<SObject> results = (List<SObject>) JSON.deserialize(
    JSON.serialize(records),
    List<SObject>.class
);
```

This round-trip is the mechanism. Apex blocks assignment of formula fields,
system fields, or `Id` through normal property setters — but **JSON
deserialization writes them anyway**. That is why `TestData` can return a
record that already looks inserted and audited, with no DML required.

### 3. Records never touch the database

Everything happens in memory. No `insert`, no SOQL, no DML rows consumed, no
triggers fired. Tests stay fast and isolated. The flip side: these records are
for mocking, not for inserting — see [Notes & Edge Cases](#notes-and-edge-cases).

## Public API

`TestData` exposes a constructor, four fluent methods, and one inner class.

> **A note on "properties":** `TestData` has no public properties. Its instance
> state — `sObjectType`, `template`, `count`, and `mockids` — is **private**
> (no access modifier in Apex means private). State can only change through the
> methods below. That keeps the builder consistent, and it is why the fluent
> API is the only supported entry point.

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| Constructor | `TestData(SObjectType sObjectType)` | `TestData` | Starts a builder bound to one object type. Required first step. |
| `put` | `put(SObjectField field, Object value)` | `TestData` | Adds or overwrites a field/value pair in the record template. When `value` is an `SObject`, it is treated as a parent relationship — see [Relationships](#relationships). |
| `count` | `count(Integer count)` | `TestData` | Sets how many records `build()` returns. Defaults to `1`. |
| `mockIds` | `mockIds()` | `TestData` | Enables synthetic Id generation so every built record gets a unique, valid-looking `Id`. Off by default (`Id` is `null`). |
| `build` | `build()` | `List<SObject>` | Produces the records from the current template and returns them. Can be called more than once on the same builder. |

### Private state

| Field | Default | Set by | Effect |
| --- | --- | --- | --- |
| `sObjectType` | — | constructor | The object type every built record is deserialized into. |
| `template` | empty map | `put` | A `Map<SObjectField, Object>` of field values applied to every record. |
| `count` | `1` | `count` | Number of records produced by `build()`. |
| `mockids` | `false` | `mockIds` | When `true`, each record receives a generated `Id`. |

### `IdService` (inner class)

`TestData` keeps one static `IdService` instance. Its single public method,
`get(SObjectType)`, returns the next sequential, valid 15-character Id for that
object type. You normally never call it directly — `mockIds()` uses it for you
— but it is a `public` inner class, so it is part of the surface.

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| `get` | `get(SObjectType sObjectType)` | `Id` | Returns the next sequential mock Id for the given object type, using that type's key prefix and a zero-padded 15-character format. |

## Notes & Edge Cases

- **No Id unless you ask.** Without `mockIds()`, `Id` is `null`. Code that keys
  records by `Id` — maps, dedupe logic, lookups — needs `mockIds()`.
- **Records in one `build()` are identical** except for their generated Ids.
  Build separately when you need different field values per record.
- **Mock Ids are not stable across the transaction.** Assert on uniqueness or
  key prefix, not on a specific Id string. The counter value depends on how
  many records of that type were built earlier in the same test run.
- **These records are for mocking, not DML.** Inserting a record with read-only
  or system fields populated will fail. Use real DML only when database behavior
  itself is the thing under test.
- **Set only the fields your assertions need.** Focused records keep tests
  readable and resilient to unrelated schema changes.
- **Cast close to usage.** `build()` returns `List<SObject>`; cast to the
  concrete type at the point you read it so setup stays generic and concise.
- **`IdService` counters are per object type.** Interleaving builds for Account
  and Contact increments each type's counter independently. Account and Contact
  never share a sequence.
