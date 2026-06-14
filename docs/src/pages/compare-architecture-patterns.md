---
layout: ../layouts/DocsLayout.astro
title: Bedrock and Common Apex Patterns | sf-bedrock docs
description: How sf-bedrock compares with raw Apex, traditional enterprise Apex frameworks, trigger frameworks, Queueables, and custom unit-of-work patterns.
eyebrow: Adoption
heading: Bedrock and Common Apex Patterns
lede: Bedrock is not trying to win every architecture argument. It chooses a lower-ceremony path for teams that want plain Apex, small seams, and incremental adoption.
sections:
  - label: Comparison Frame
    href: "#comparison-frame"
  - label: Raw Apex
    href: "#raw-apex"
  - label: Traditional Enterprise Frameworks
    href: "#traditional-enterprise-frameworks"
  - label: Trigger Frameworks
    href: "#trigger-frameworks"
  - label: Queueables
    href: "#queueables"
  - label: Unit Of Work Patterns
    href: "#unit-of-work-patterns"
  - label: When Bedrock Fits
    href: "#when-bedrock-fits"
---

## Comparison Frame

Most Apex architecture choices are tradeoffs. Bedrock's preferred tradeoff is a
small mental model:

- Keep production code plain.
- Add seams only where they make tests, operations, or limits better.
- Let teams adopt one tool at a time.
- Keep the supported API surface small enough to inspect.

This page is not a teardown of other patterns. Many Salesforce orgs run well on
raw Apex, traditional enterprise frameworks, trigger frameworks, direct
Queueables, or custom unit-of-work implementations. Bedrock is for teams that
want enterprise safety with less ceremony.

## Raw Apex

Raw Apex is the easiest way to start. It is also the baseline Bedrock tries to
preserve: readable classes, direct control flow, and familiar platform behavior.

Raw Apex starts to hurt when:

- Tests require DML and SOQL setup for simple service behavior.
- Trigger-side writes scatter across several services.
- Queueable work has no business-level status or retry path.
- Scheduled jobs consume many org-level scheduled Apex slots.

Bedrock keeps the raw Apex feel but adds focused seams for the parts that become
hard to test or operate.

## Traditional Enterprise Frameworks

Traditional enterprise Apex frameworks often provide selectors, domains,
service conventions, unit-of-work abstractions, and dependency injection as one
cohesive model.

That can be powerful for teams that want a comprehensive architecture and can
train every developer into the same mental model. The tradeoff is ceremony:
debugging can move through framework layers before reaching the business
behavior.

Bedrock chooses less surface area. It does not require a team to adopt a full
domain-selector-service stack before they can write a useful test. It offers
small tools that can fit into an existing architecture.

## Trigger Frameworks

Trigger frameworks usually focus on routing trigger events into handler methods.
Bedrock's `TriggerHandler` does that, but keeps the contract small: override the
context hooks you need and keep trigger logic out of the trigger body.

Bedrock does not try to hide every trigger concern. Recursion guards, metadata
disable switches, and bypass policies are org-specific decisions. Document them
near the domain code that owns them.

Use `TriggerHandler` when routing and context clarity are the problem. Add
`RecordBuffer` when related writes should be grouped and flushed at a controlled
boundary.

## Queueables

Direct Queueables are the normal Salesforce tool for background Apex. They are a
good fit for focused work with simple operational needs.

They become harder to govern when:

- Trigger-originated automation runs inside existing async contexts.
- One job needs to create follow-up work safely.
- Operators need to see backlog, retries, errors, or job configuration.
- A team needs per-user concurrency tuning.

`Async` is Bedrock's record-driven alternative for those cases. It records one
work item per record Id, drains work in batches, saves outcomes, and keeps
follow-up work inside a managed framework path.

## Unit Of Work Patterns

Unit-of-work implementations can coordinate related DML well, but they can also
become difficult to understand when they track too much state or hide too much
behavior.

`RecordBuffer` is intentionally smaller. It stages records by operation and
object type, then flushes grouped DML at an explicit point. It is not a full
transaction manager. It is a controlled buffer for the trigger and service paths
that need one.

## When Bedrock Fits

Bedrock is a strong fit when a team wants:

- Database-free service tests.
- Small DML and query seams.
- Realistic in-memory test records.
- Clear trigger routing without a large trigger framework.
- Explicit buffered DML.
- Tracked, retryable, visible background work.
- Metadata-driven scheduled jobs.
- Incremental adoption inside an existing org.

It is a weaker fit when the team wants a single comprehensive architecture
framework, a packaged commercial support model, generated selectors, or a
security engine that owns CRUD and FLS decisions automatically.
