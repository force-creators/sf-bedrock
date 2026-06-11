# Generic — Agent Guide

Component guide for the `Generic` library. Global conventions (Apex style,
testing rules, the Salesforce MCP deploy/validate workflow, architecture
layers) live in the repo root `AGENTS.md`. Inspect the code in this folder
before depending on exact method behavior.

## What it is

`Generic` is the helper for generic JSON and unstructured data. It is intended
as the toolkit for turning generic data into strongly typed Apex contracts and
for parsing or building complex JSON payloads.

## Current shape

- Construct from empty state, a JSON string, or `Map<String, Object>`.
- Read values by path, including list-style path segments.
- Coerce read values to common primitive, collection, or typed Apex targets.
- Write values by path into nested maps.
- Serialize back to JSON.
- Convert generic data into typed `SObject` records.
- Override `mapping()` and `transform()` for reusable transformations.

## Composition

The planned `Event` framework (see `../event/ROADMAP.md`) uses `Generic` as the
envelope for stored event payloads, reusing its `mapping()` / `transform()`
overrides and `toSObject(...)` conversion.
