# TriggerHandler — Agent Guide

Component guide for the `TriggerHandler` library. Global conventions (Apex
style, testing rules, the Salesforce MCP deploy/validate workflow, architecture
layers) live in the repo root `AGENTS.md`. Inspect the code in this folder
before depending on exact method behavior.

## What it is

`TriggerHandler` is a lightweight trigger handler framework. It coordinates
Bedrock tools around the domain layer without forcing a heavy trigger pattern.

## Current shape

- `run()` exits unless `Trigger.isExecuting`.
- Starts `RecordBuffer` before dispatch and flushes it after dispatch.
- Dispatches all standard trigger operations to protected virtual hooks.
- Exposes empty hook methods for before/after insert, update, delete, and
  undelete.
- Is intentionally extensible so other frameworks or setup/teardown steps can
  be added by subclasses.

## Composition

`TriggerHandler` coordinates Bedrock lifecycle hooks around domain logic and
builds on `RecordBuffer` (see `../record-buffer/AGENTS.md`). The `Async`
framework's `AsyncTriggerHandler` already extends it.
