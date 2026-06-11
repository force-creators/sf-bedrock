# TestData — Agent Guide

Component guide for the `TestData` library. Global conventions (Apex style,
testing rules, the Salesforce MCP deploy/validate workflow, architecture
layers) live in the repo root `AGENTS.md`. Inspect the code in this folder
before depending on exact method behavior.

## What it is

`TestData` builds mockable and insertable Salesforce records. It uses JSON
serialization so tests can set fields that are normally read-only, such as
audit fields, and it can generate mock Ids per `SObjectType`. This is meant to
reduce bloated unit tests where unrelated setup dominates runtime.

## Current shape

- Fluent builder around an `SObjectType`.
- `put(SObjectField, Object)` stores field values for generated records.
- `count(Integer)` controls how many records `build()` returns.
- `mockIds()` assigns synthetic Ids using the object's key prefix.
- Relationship values can be provided as `SObject` instances.

## Usage

When building mock data, call `mockIds()` by default. Keep data setup focused
on the behavior under test; avoid expensive, unrelated setup.

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
