# FeatureFlag — Agent Guide

Component guide for the `FeatureFlag` library. Global conventions (Apex style,
testing rules, the Salesforce MCP deploy/validate workflow, architecture
layers) live in the repo root `AGENTS.md`. Inspect the code in this folder
before depending on exact method behavior.

## What it is

`FeatureFlag` provides feature-toggle lookups backed by `Feature_Flag__mdt`.
It caches lookups by name for the current transaction and exposes test-only
helpers to seed or clear cached values.

## Current shape

- `isEnabled(String)` fails closed for blank names and missing records.
- `get(String)` reads `Feature_Flag__mdt` by `Name__c` and caches the result
  in memory.
- `set(String, Boolean)` is test-visible and seeds the cache directly.
- `clearCache()` is test-visible and clears the in-memory cache.

## Schema

Relies on the `Feature_Flag__mdt` custom metadata type (`Name__c` plus the
enablement field), under this component's `objects` folder.
