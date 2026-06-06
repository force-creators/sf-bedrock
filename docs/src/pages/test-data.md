---
layout: ../layouts/DocsLayout.astro
title: TestData | sf-bedrock docs
description: Technical documentation and usage examples for the sf-bedrock TestData Apex utility.
eyebrow: Foundation API
heading: TestData
lede: Build focused Salesforce records for Apex tests without expensive setup, broad fixture factories, or real DML when behavior can be proven with mock records.
sections:
  - label: Purpose
    href: "#purpose"
  - label: Examples
    href: "#examples"
  - label: Relationships
    href: "#relationships"
  - label: Method Reference
    href: "#method-reference"
  - label: Testing Notes
    href: "#testing-notes"
---

## Purpose

`TestData` is a fluent builder for creating `SObject` records in unit tests. It keeps setup close to the behavior under test: pick an object type, set important fields, optionally generate mock IDs, and build records without touching the database.

Use it when tests need realistic records without database side effects.

Skip it when tests must prove validation rules, trigger execution, sharing, or committed data behavior.

## Examples

### Create one typed record

By default, `build()` creates one record and leaves `Id` empty.

```apex
Account account = (Account) new TestData(Account.sObjectType)
  .put(Account.Name, 'Bedrock')
  .build()[0];

Assert.areEqual(
  'Bedrock',
  account.Name,
  'Expected TestData to populate the requested field.'
);
```

### Generate a focused list

Use `count(Integer)` when behavior depends on list size.

```apex
List<SObject> contacts = new TestData(Contact.sObjectType)
  .put(Contact.LastName, 'Subscriber')
  .count(3)
  .build();

Assert.areEqual(
  3,
  contacts.size(),
  'Expected count(3) to build exactly three records.'
);
```

### Build mock records with synthetic IDs

Call `mockIds()` when production code expects stable Salesforce-style IDs.

```apex
List<SObject> accounts = new TestData(Account.sObjectType)
  .put(Account.Name, 'Mocked')
  .mockIds()
  .count(2)
  .build();

Account first = (Account) accounts[0];
Account second = (Account) accounts[1];

Assert.areNotEqual(
  first.Id,
  second.Id,
  'Expected each generated mock Id to be unique.'
);
```

## Relationships

If a `put` value is an `SObject`, `TestData` stores the related record ID on the lookup field and hydrates the relationship property.

```apex
Account parent = (Account) new TestData(Account.sObjectType)
  .put(Account.Name, 'Parent Account')
  .mockIds()
  .build()[0];

Contact contact = (Contact) new TestData(Contact.sObjectType)
  .put(Contact.LastName, 'Child Contact')
  .put(Contact.AccountId, parent)
  .mockIds()
  .build()[0];

Assert.areEqual(parent.Id, contact.AccountId, 'Expected lookup Id.');
Assert.areEqual('Parent Account', contact.Account.Name, 'Expected relationship fields.');
```

## Method Reference

- `new TestData(type)`: starts a builder for the provided `SObjectType`.
- `put(field, value)`: adds a field value to the record template.
- `count(number)`: sets how many records `build()` returns.
- `mockIds()`: enables synthetic ID generation.
- `build()`: creates records and returns `List<SObject>`.

## Testing Notes

- Prefer focused records: set only fields needed by assertions.
- Use `mockIds()` by default in service tests.
- Cast near usage so setup stays generic and concise.
- Use real DML only when database behavior is the thing being tested.
