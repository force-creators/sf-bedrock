# Query and QueryMock — Agent Guide

Component guide for the `Query` library. Global conventions (Apex style,
testing rules, the Salesforce MCP deploy/validate workflow, architecture
layers) live in the repo root `AGENTS.md`. Inspect the code in this folder
before depending on exact method behavior.

## What it is

`Query` is the query dependency injection layer. It provides a static facade
over a virtual query implementation so test code can replace query behavior.

## Current shape

- `Query.records(List<SObject>)` delegates to the active query instance.
- Base `Query.query(...)` returns the provided records.
- `QueryMock` can return a fixed record or record list.
- `QueryMock.Multiple` can return different result sets over sequential calls
  and throws when no staged result remains.

## Usage and testing

- All query logic in the framework should go through `Query.records(...)`.
- Unit tests should use mocks instead of real SOQL when testing service
  behavior. Use `QueryMock` for a single query result. Use `QueryMock.Multiple`
  when more than one query response is needed — it returns values in the same
  order they are staged.

## Composition

`Query` is one of the dependency-injection foundations (`TestData`, `DML`,
`Query`). The `Async` framework's `QueryService` reads `Async__c` and
`Async_Config__mdt` through `Query`. The planned `Selector` framework
(see `../selector/ROADMAP.md`) builds on `Query`.
