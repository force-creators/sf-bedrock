# RecordBuffer — Agent Guide

Component guide for the `RecordBuffer` library. Global conventions (Apex style,
testing rules, the Salesforce MCP deploy/validate workflow, architecture
layers) live in the repo root `AGENTS.md`. Inspect the code in this folder
before depending on exact method behavior.

## What it is

`RecordBuffer` stages DML between services in a trigger context. It is designed
to avoid repeated DML work and reduce recursion risk when multiple services
update the same object type in the same trigger flow.

## Current shape

- Maintains a stack of trigger contexts.
- Lazily starts a context when code stages or reads records without calling
  `start()` first.
- Stages inserts when records have no Id.
- Stages updates in a `Map<Id, SObject>` when records have Ids.
- Groups staged work by `SObjectType`.
- Includes helpers for retrieving staged update records by Id; inspect edge
  behavior before relying on null or empty inputs.
- `flush()` merges inserts and updates by object type and calls
  `DML.upsertRecords(...)` once per type.

## Composition

`RecordBuffer` coordinates DML staging in trigger flows and writes through
`DML`. `TriggerHandler` (see `../trigger-handler/AGENTS.md`) starts a
`RecordBuffer` context before dispatch and flushes it after dispatch.
