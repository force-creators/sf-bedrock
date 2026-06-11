# DML and DMLMock — Agent Guide

Component guide for the `DML` library. Global conventions (Apex style, testing
rules, the Salesforce MCP deploy/validate workflow, architecture layers) live
in the repo root `AGENTS.md`. Inspect the code in this folder before depending
on exact method behavior.

## What it is

`DML` is the DML dependency injection layer. It exposes static methods that
delegate to an injectable service instance. Production behavior performs normal
Apex DML. Tests can use `DML.setMock(...)` with `DMLMock`.

## Current shape

- `DML` extends `DML.Service`.
- `DML.Service` exposes virtual insert, update, upsert, delete, and undelete
  methods.
- `DML.upsertRecords(...)` supports both plain upsert and upsert with an
  external Id field.
- `DMLMock` records insert, update, upsert, delete, and undelete calls in
  public list properties.

## Usage and testing

- All DML in the framework should go through `DML`.
- Unit tests should use mocks instead of real DML when testing service
  behavior. Use `DMLMock` to capture DML calls and assert the operation, count,
  record type, and important field mutations.

## Composition

`DML` is one of the dependency-injection foundations (`TestData`, `DML`,
`Query`). `RecordBuffer.flush()` and the `Async` framework's `WorkService`
perform their writes through `DML`.
