---
layout: ../layouts/DocsLayout.astro
title: Selector | sf-bedrock docs
description: Build reusable Id-based SOQL selectors with transaction caching, Platform Cache support, and cache keys derived from the query contract.
eyebrow: Tools
heading: Selector
lede: Selector turns repeated Id-based queries into reusable classes. It builds SOQL from a field set, optional where clauses, and a shared contract key so services can reuse records inside one transaction or through Platform Cache.
sections:
  - label: Overview
    href: "#overview"
  - label: Quickstart
    href: "#quickstart"
  - label: Examples
    href: "#examples"
  - label: Query Contracts
    href: "#query-contracts"
  - label: Transaction Caching
    href: "#transaction-caching"
  - label: Platform Cache
    href: "#platform-cache"
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

`Selector` is the Bedrock query encapsulation layer. It builds one Id-based SOQL
query from an SObject name, a set of selected fields, and optional `WHERE`
fragments. It also gives selectors a stable contract key:

```text
ClassName:contractHashCode
```

That key lets the same selector class keep separate caches for different field
sets or filters. If a selector later adds a field or relationship, the contract
hash changes and old Platform Cache entries stop matching automatically.

**Use `Selector` when** multiple services need the same records by Id, and the
selected fields or filters are meaningful enough to live in one reusable place.
Use `Selector.Once` when the win is avoiding repeat SOQL inside one Apex
transaction. Use `Selector.Cached` when the same records should also be reused
through Platform Cache across transactions.

**Reach for `Query` or a service instead when** the code only needs a test seam
for a list it already has, or when the read is not naturally Id-based. Selector
is not a general query builder for every SOQL shape.

## Quickstart

Create a typed selector by extending `Selector.Once`. Pass the object name and
the fields the selector needs. `Id` is added automatically.

```apex
public inherited sharing class AccountSelector extends Selector.Once {
    public AccountSelector() {
        super('Account', new Set<String>{ 'Name', 'Owner.Name' });
    }

    public static List<Account> records(Set<Id> ids) {
        return (List<Account>) Selector.instance(new AccountSelector()).records(ids);
    }
}
```

Call the static facade from services:

```apex
List<Account> accounts = AccountSelector.records(accountIds);
```

Every caller using the same selector class and query contract in the same Apex
transaction receives records from the same `Selector.Once` instance.

## Examples

### Add where clauses

Where clauses are constructor inputs. The base selector always adds the
`Id IN :ids` clause; your clauses are appended with `AND`.

```apex
public inherited sharing class ActiveAccountSelector extends Selector.Once {
    public ActiveAccountSelector() {
        super(
            'Account',
            new Set<String>{ 'Name', 'Owner.Name' },
            new Set<String>{ 'IsDeleted = false' }
        );
    }

    public static List<Account> records(Set<Id> ids) {
        return (List<Account>) Selector.instance(new ActiveAccountSelector()).records(ids);
    }
}
```

The generated SOQL shape is:

```sql
SELECT Id, Name, Owner.Name
FROM Account
WHERE Id IN :ids AND (IsDeleted = false)
```

### Return one record

`record(id)` calls `records(new Set<Id>{ id })` and returns the first record, or
`null` when no record is loaded.

```apex
Account account = (Account) Selector.instance(new AccountSelector()).record(accountId);
```

### Return a map

`recordsById(ids)` returns a `Map<Id, SObject>` built from the selector result.

```apex
Map<Id, Account> accountsById = new Map<Id, Account>(
    (List<Account>) Selector.instance(new AccountSelector()).records(accountIds)
);
```

Use `recordsById(...)` directly when a generic `Map<Id, SObject>` is enough:

```apex
Map<Id, SObject> recordsById = Selector.instance(new AccountSelector()).recordsById(accountIds);
```

### Use Platform Cache

Extend `Selector.Cached` and provide a partition name or a `PlatformCache`
adapter.

```apex
public inherited sharing class CachedAccountSelector extends Selector.Cached {
    public CachedAccountSelector() {
        super('Account', new Set<String>{ 'Name', 'Owner.Name' }, 'Bedrock');
    }

    public static List<Account> records(Set<Id> ids) {
        return (List<Account>) Selector.instance(new CachedAccountSelector()).records(ids);
    }
}
```

The selector first checks the transaction cache, then Platform Cache, then SOQL.
Records queried from the database are written back to Platform Cache using
`cacheKey(record.Id)`.

## Query Contracts

The contract is a `Set<String>` containing:

- `FROM:<sObjectName>`
- `SELECT:<fieldOrRelationship>` for every selected field
- `WHERE:<whereClause>` for every custom where clause

The selector key is `className() + ':' + contract().hashCode()`. The class name
comes from the Apex string representation of the selector instance:

```apex
public virtual String className() {
    return String.valueOf(this).substringBefore(':');
}
```

Because the selected fields, relationships, object name, and where clauses are
part of the contract, these two selectors do not share a cache key:

```apex
new AccountSelector(new Set<String>{ 'Name' });
new AccountSelector(new Set<String>{ 'Name', 'Owner.Name' });
```

> The hash is a query-shape version. It is not a record freshness check. Record
> freshness still depends on transaction scope, Platform Cache eviction, TTL,
> or explicit cache removal outside Selector.

## Transaction Caching

`Selector.Once` stores loaded records in an instance `Map<Id, SObject>`. It only
queries Ids that are not already loaded:

```apex
Selector.Once selector = (Selector.Once) Selector.instance(new AccountSelector());

List<SObject> first = selector.records(accountIds);   // queries missing Ids
List<SObject> second = selector.records(accountIds);  // returns loaded records
```

The shared instance comes from `Selector.instance(selector)`. It stores selectors
in static transaction state keyed by `selector.key()`, so separate services can
converge on the same selector instance without passing it around manually.

## Platform Cache

`Selector.Cached` extends `Selector.Once`. It keeps the same transaction cache,
then adds a Platform Cache lookup for Ids that are missing from the transaction.

For each missing Id, it reads:

```text
ClassName:contractHashCode:recordId
```

If the cache returns an `SObject`, that record is loaded into the transaction
cache. Any Ids still missing after cache reads are queried with SOQL. Queried
records are written back to the cache under their `cacheKey(record.Id)`.

Use the partition-name constructor for normal org cache:

```apex
super('Account', new Set<String>{ 'Name' }, 'Bedrock');
```

Use the `PlatformCache` constructor when the selector needs a specific adapter,
or when tests should pass a `PlatformCacheMock` directly.

```apex
PlatformCacheMock mock = new PlatformCacheMock('Bedrock');
Selector.Cached selector = new CachedAccountSelector(mock);
```

## Testing

For selector tests, prefer proving behavior directly:

- query text includes the required fields and where clauses
- the key changes when the field set or where clauses change
- `Selector.Once` avoids a repeat SOQL query for the same Id
- `Selector.Cached` reads from and writes to `PlatformCacheMock`

### Prove transaction caching

```apex
@istest static void accountSelector_usesTransactionCache() {
    Account account = new Account(Name = 'Bedrock Once');
    DML.insertRecords(new List<SObject>{ account });

    Selector.Once selector = new AccountSelector();

    Integer queriesBefore = Limits.getQueries();
    selector.records(new Set<Id>{ account.Id });
    Integer queriesAfterFirstCall = Limits.getQueries();
    selector.records(new Set<Id>{ account.Id });

    Assert.areEqual(queriesBefore + 1, queriesAfterFirstCall,
        'First selector call should query the missing account.');
    Assert.areEqual(queriesAfterFirstCall, Limits.getQueries(),
        'Second selector call for the same Id should use the transaction cache.');
}
```

### Prove Platform Cache reads

```apex
@istest static void cachedSelector_usesPlatformCache() {
    Account account = (Account) new TestData(Account.sObjectType)
        .put(Account.Name, 'Cached')
        .mockIds()
        .build()[0];

    PlatformCacheMock cacheMock = new PlatformCacheMock('Bedrock');
    Selector.Cached selector = new CachedAccountSelector(cacheMock);
    cacheMock.valuesByKey.put(selector.cacheKey(account.Id), account);

    List<SObject> records = selector.records(new Set<Id>{ account.Id });

    Assert.areEqual(1, records.size(), 'Cached selector should return the cached record.');
    Assert.areEqual('Cached', ((Account) records[0]).Name,
        'Cached selector should preserve the cached SObject payload.');
    Assert.areEqual(new List<String>{ selector.cacheKey(account.Id) }, cacheMock.gets,
        'Cached selector should read the expected Platform Cache key.');
}
```

### Test helper classes

Keep tiny test selectors local to the test class:

```apex
inherited sharing class AccountSelector extends Selector.Once {
    AccountSelector() {
        super('Account', new Set<String>{ 'Name' });
    }
}

inherited sharing class CachedAccountSelector extends Selector.Cached {
    CachedAccountSelector(PlatformCache cache) {
        super('Account', new Set<String>{ 'Name' }, cache);
    }
}
```

## How It Works

Three ideas explain everything `Selector` does.

### 1. The constructor defines the query shape

A selector is built from three inputs: object name, selected fields, and optional
where clauses. The constructor requires an object name and at least one field.
It adds `Id` automatically because every cache path is Id-based.

### 2. The query contract versions the cache

`contract()` returns a set of strings representing the object, fields, and
where clauses. `contractHashCode()` returns that set's hash code. `key()` joins
the runtime class name and hash:

```apex
AccountSelector:123456789
```

That means two selectors with different field sets or filters use different
transaction instances and different Platform Cache keys.

### 3. Cache lookup is layered

Base `Selector.records(ids)` runs the query every time. `Selector.Once` checks
the transaction `Map<Id, SObject>` first. `Selector.Cached` checks that same map,
then Platform Cache, then SOQL. Each layer only asks the next layer for the Ids
still missing.

## Public API

The selector API lives in one `public virtual inherited sharing` class,
`Selector`, with two nested selector variants: `Selector.Once` and
`Selector.Cached`.

> **A note on access modifiers:** `sObjectName`, `fields`, `whereClauses`, and
> `loadedRecordsById` are `protected` state for selector subclasses.
> `instancesByKey` has no access modifier, so it is private internal state except
> where `@TestVisible` allows tests to reset it. The supported surface is the
> methods and constructors below.

### `Selector`

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| Constructor | `Selector(String sObjectName, Set<String> fields)` | `Selector` | Creates a selector for an object and selected fields. Adds `Id` automatically. |
| Constructor | `Selector(String sObjectName, Set<String> fields, Set<String> whereClauses)` | `Selector` | Creates a selector with additional where clauses. Blank where clauses are ignored. |
| `instance` | `instance(Selector selector)` | `Selector` | Static transaction registry. Returns the existing selector for `selector.key()`, or stores and returns the provided selector. |
| `records` | `records(Set<Id> ids)` | `List<SObject>` | Returns an empty list for null or empty Id sets. Otherwise calls `query(ids)`. |
| `record` | `record(Id id)` | `SObject` | Calls `records(...)` for one Id and returns the first record, or `null`. |
| `recordsById` | `recordsById(Set<Id> ids)` | `Map<Id, SObject>` | Builds a map from the records returned by `records(ids)`. |
| `query` | `query(Set<Id> ids)` | `List<SObject>` | Runs `Database.query(queryText(ids))` through `Query.records(...)`. |
| `key` | `key()` | `String` | Returns `className() + ':' + contractHashCode()`. |
| `cacheKey` | `cacheKey(Id id)` | `String` | Returns `key() + ':' + id`. Used by `Selector.Cached`. |
| `contractHashCode` | `contractHashCode()` | `Integer` | Returns `contract().hashCode()`. |
| `contract` | `contract()` | `Set<String>` | Returns the object, selected fields, and where clauses as contract strings. |
| `className` | `className()` | `String` | Returns `String.valueOf(this).substringBefore(':')`. |

> `clearInstances()` and `queryText(Set<Id> ids)` are `@TestVisible`, not
> production API. `clearInstances()` resets the static registry. `queryText(...)`
> exposes generated SOQL for focused tests.

### `Selector.Once` (inner class, extends `Selector`)

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| Constructor | `Once(String sObjectName, Set<String> fields)` | `Once` | Creates a transaction-cached selector. |
| Constructor | `Once(String sObjectName, Set<String> fields, Set<String> whereClauses)` | `Once` | Creates a transaction-cached selector with extra where clauses. |
| `records` | `records(Set<Id> ids)` | `List<SObject>` | `override virtual`. Queries only Ids not already loaded into the instance map, then returns loaded records in requested Id iteration order. |

### `Selector.Cached` (inner class, extends `Selector.Once`)

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| Constructor | `Cached(String sObjectName, Set<String> fields, PlatformCache cache)` | `Cached` | Creates a cached selector with a provided cache adapter. |
| Constructor | `Cached(String sObjectName, Set<String> fields, String partitionName)` | `Cached` | Creates a cached selector backed by `new PlatformCache.Org(partitionName)`. |
| Constructor | `Cached(String sObjectName, Set<String> fields, Set<String> whereClauses, PlatformCache cache)` | `Cached` | Creates a cached selector with where clauses and a provided cache adapter. |
| Constructor | `Cached(String sObjectName, Set<String> fields, Set<String> whereClauses, String partitionName)` | `Cached` | Creates a cached selector with where clauses backed by org cache. |
| `records` | `records(Set<Id> ids)` | `List<SObject>` | `override`. Reads transaction cache, then Platform Cache, then SOQL. Writes queried records back to Platform Cache. |

### `Selector.SelectorException` (inner class, extends `Exception`)

Thrown when required constructor inputs are missing: blank SObject name, empty
field set, or null cache adapter for `Selector.Cached`.

## Notes & Edge Cases

- **Selector is Id-based.** The base query always includes `WHERE Id IN :ids`.
  If a read is not naturally keyed by record Id, put it in a service or a custom
  query method instead of forcing it through this API.

- **Where clauses are raw SOQL fragments.** Selector wraps each fragment in
  parentheses and joins them with `AND`. It does not parse, escape, bind, or
  validate the text you pass.

- **The field and where sets are copied into internal sets.** Mutating the set
  used to construct a selector later does not change that selector's query
  contract.

- **Set iteration order is not a sorting contract.** `Selector.Once` returns
  records in the iteration order of the requested `Set<Id>`, minus records that
  were not found. Do not use it as an ordering API.

- **`Set.hashCode()` can collide.** The cache key intentionally uses the set hash
  because the contract is developer-owned and compact. If a future version needs
  stronger collision resistance, the same `contract()` method can be canonicalized
  and digested without changing how selectors define their fields and clauses.

- **Platform Cache entries are versioned, not actively removed.** Changing the
  field set or where clauses changes the cache key, so old entries stop matching.
  They remain in Platform Cache until the platform evicts them or they expire.

- **Cached records are full SObjects.** `Selector.Cached` only treats a cache hit
  as valid when `cache.get(...)` returns an `SObject`.

- **Production SOQL still goes through `Query.records(...)`.** Tests that need
  to intercept the database result can still use `QueryMock`, but remember that
  Apex evaluates `Database.query(...)` before `Query.records(...)` receives the
  list.
