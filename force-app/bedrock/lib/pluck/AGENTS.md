# Pluck — Agent Guide

Component guide for the `Pluck` library. Global conventions (Apex style,
testing rules, the Salesforce MCP deploy/validate workflow, architecture
layers) live in the repo root `AGENTS.md`. Inspect the code in this folder
before depending on exact method behavior.

## What it is

`Pluck` is a small static utility for pulling `Set<Id>` values out of record
lists, used by `Async` when turning records into work items.

## Current shape

- `Pluck.ids(List<SObject>)` collects non-null record Ids.
- `Pluck.ids(SObjectField, List<SObject>)` collects non-null Ids from a lookup
  or reference field.

## Composition

`Pluck` provides the small `Set<Id>` helpers that feed list-driven APIs like
`Async.enqueue` (see `../async/AGENTS.md`).
