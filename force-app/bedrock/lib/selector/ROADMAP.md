# Selector — Roadmap

A future Bedrock framework. This folder has no implemented code yet — it is
proposed work. Cross-cutting roadmap principles and feature sequencing live in
the repo root `ROADMAP.md`.

These are intended designs, not finalized public APIs. Ask before locking
names, schemas, or behavior that does not exist yet.

## Selector

Status: future. Builds on the implemented `Query` (`../query/AGENTS.md`).

The planned query encapsulation pattern — make simple queries testable and
reusable. A one-query selector variant is planned but **not named yet**.
Candidate names: `Selector.OneTime`, `Selector.Once`, `Selector.Gateway`.
Intended behavior:

- Query by a fixed set of Id values.
- Store results in `Map<Id, SObject>`.
- Return cached records when the same Id is requested again, avoiding repeat
  queries for records already loaded.

Do not choose the final API name without asking — weigh the readability of
`Once` against the architectural meaning of `Gateway`.

## Selector.Cached

Status: future. Builds on Selector and the implemented `PlatformCache`
(`../platform-cache/AGENTS.md`).

An extension of the one-query selector behavior that stores records in
Salesforce Platform Cache.
