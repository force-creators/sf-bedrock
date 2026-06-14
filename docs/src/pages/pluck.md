---
layout: ../layouts/DocsLayout.astro
title: Pluck | sf-bedrock docs
description: A tiny static utility that turns a list of SObject records into a deduped Set<Id> — either from each record's own Id or from a lookup field on each record.
eyebrow: Tools
heading: Pluck
lede: Pluck turns a list of SObject records into a deduped `Set<Id>` in one call — either from each record's own Id, or from a lookup field on each record. It is what `Async.enqueue` uses internally to build its work-item payload.
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

`Pluck` solves a small, recurring problem: you have a `List<SObject>` and you
need a `Set<Id>`. Either the records' own Ids, or the Id stored in a lookup
field on each record. Writing the null-check loop by hand every time is noise.
`Pluck` moves that loop into one place and gives you back a clean set.

**Use `Pluck` when** you need to collect record Ids or lookup-field Ids from a
list of records to feed a `Set<Id>`-based API. Common cases: passing record
Ids to `Async.enqueue`, building a key set for a `Map<Id, SObject>`, or
preparing an Id set before a query.

**Reach for a full collection framework or SOQL instead when** you need to
group records by field, filter them, sort them, or aggregate values — anything
more complex than extracting Ids. `Pluck` has exactly two methods and does
exactly one thing. It is not a general-purpose collection utility.

## Quickstart

Collect the Ids of a list of records:

```apex
Set<Id> ids = Pluck.ids(records);
```

Collect the value of a lookup field on each record:

```apex
Set<Id> accountIds = Pluck.ids(Contact.AccountId, contacts);
```

## Examples

### Collect record Ids

The simplest call: pass a list of records and get back the non-null Ids.

```apex
List<Account> accounts = [
    SELECT Id, Name
    FROM Account
    WHERE Industry = 'Technology'
];
Set<Id> accountIds = Pluck.ids(accounts);
```

### Collect a lookup field — parent Account Ids from a Contact list

The second overload reads the value of any `SObjectField` that holds an Id
(a lookup or master-detail field) and casts it to `Id`. Here, every Contact's
`AccountId` field is collected into a set of parent Account Ids:

```apex
List<Contact> contacts = [
    SELECT Id, AccountId
    FROM Contact
    WHERE MailingCountry = 'USA'
];
Set<Id> parentAccountIds = Pluck.ids(Contact.AccountId, contacts);
```

Records where `AccountId` is null are skipped automatically.

### Feeding Async.enqueue

`Async.enqueue` accepts either a `List<SObject>` or a `Set<Id>`. When you
already have a Set, pass it directly. When you only have a list and want to
build the set yourself, `Pluck` gives you the same result the framework
produces internally:

```apex
// These two calls are equivalent:
Async.enqueue(SyncOrderJob.class, orders);
Async.enqueue(SyncOrderJob.class, Pluck.ids(orders));
```

## Testing

`Pluck` is a pair of pure static methods with no dependencies and no state —
there is nothing to mock. Build records with `TestData`, call `Pluck.ids`, and
assert on the resulting set.

### Unit test: record Ids

```apex
@istest static void ids_collectsNonNullRecordIds() {
    List<SObject> accounts = new TestData(Account.sObjectType)
        .put(Account.Name, 'Bedrock')
        .mockIds()
        .count(3)
        .build();

    Set<Id> result = Pluck.ids(accounts);

    Assert.areEqual(3, result.size(),
        'Expected Pluck.ids to collect one Id per record.');
    for (SObject account : accounts) {
        Assert.isTrue(result.contains(account.Id),
            'Expected the result set to contain each record\'s Id.');
    }
}
```

### Unit test: lookup field, with a null skipped

```apex
@istest static void ids_plucksLookupField_skipsNulls() {
    Account parent = (Account) new TestData(Account.sObjectType)
        .put(Account.Name, 'Parent')
        .mockIds()
        .build()[0];

    List<SObject> contacts = new TestData(Contact.sObjectType)
        .put(Contact.LastName, 'Smith')
        .put(Contact.AccountId, parent.Id)
        .mockIds()
        .count(2)
        .build();

    // A third contact with no AccountId — should be excluded.
    List<SObject> unlinked = new TestData(Contact.sObjectType)
        .put(Contact.LastName, 'Jones')
        .mockIds()
        .count(1)
        .build();
    contacts.addAll(unlinked);

    Set<Id> result = Pluck.ids(Contact.AccountId, contacts);

    Assert.areEqual(1, result.size(),
        'Expected exactly one unique parent Account Id, with the null-AccountId contact excluded.');
    Assert.isTrue(result.contains(parent.Id),
        'Expected the result set to contain the parent Account Id.');
}
```

## How It Works

Two ideas explain everything `Pluck` does.

### 1. A null-guarded loop into a Set

Both methods are a single `for` loop. Each iteration checks for null before
adding to the `Set<Id>`. If the value is null, the record is skipped silently:

```apex
for (SObject record : records) {
    if (record.Id != null) ids.add(record.Id);
}
```

The second overload does the same check on the field value, then casts it to
`Id` before adding it:

```apex
for (SObject record : records) {
    if (record.get(field) != null) ids.add((Id) record.get(field));
}
```

### 2. Set semantics give deduplication for free

Both methods return a `Set<Id>`. If the same Id appears on multiple records
(for example, two contacts sharing the same `AccountId`), the set absorbs the
duplicate without extra logic. The caller gets a distinct Id set with no
additional work.

> `Pluck` is intentionally minimal. The loop and the cast are the whole
> implementation. There is no registry, no configuration, and no extension
> point. Its value is in naming the pattern and keeping the null check out of
> every call site.

## Public API

`Pluck` is declared `public with sharing` and exposes two static methods. It
has no inner types, no instance state, and no test-only members.

> **A note on access modifiers:** `Pluck` has no public properties. Its methods
> are `public static` and return a new `Set<Id>` on every call. There is no
> shared state between calls.

| Method | Signature | Returns | Description |
| --- | --- | --- | --- |
| `ids` | `ids(List<SObject> records)` | `Set<Id>` | Returns the non-null `Id` of each record in the list. Duplicates collapse; null Ids are skipped. |
| `ids` | `ids(SObjectField field, List<SObject> records)` | `Set<Id>` | Returns the non-null value of `field` on each record, cast to `Id`. Duplicates collapse; null values are skipped. |

## Notes & Edge Cases

- **Null Ids are silently skipped.** If a record has no Id — for example, a
  record that was built without `mockIds()` or was never inserted — it is
  excluded from the result. The method does not throw.

- **Null field values are silently skipped.** The second overload checks
  `record.get(field) != null` before casting. A contact with a null
  `AccountId` contributes nothing to the result set.

- **Duplicates collapse automatically.** Because the return type is `Set<Id>`,
  passing ten contacts that all share the same `AccountId` yields a one-element
  set. No extra deduplication step is needed.

- **The second overload casts the field value to `Id`.** Pass a field that
  actually holds an `Id` value — a lookup, master-detail, or other reference
  field. If the field's runtime value is not castable to `Id` (for example, a
  `String` field that happens to contain an Id-shaped string), it will throw a
  `System.TypeException` at runtime.

- **An empty list returns an empty set.** Passing `new List<SObject>()` to
  either overload returns an empty `Set<Id>` and does not throw.

- **`Pluck` is not a query or collection framework.** It only extracts Ids —
  no filtering, sorting, grouping, or aggregating. If you need richer
  collection operations, write them directly or consider a dedicated selector.
