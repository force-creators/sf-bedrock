---
layout: ../layouts/DocsLayout.astro
title: Adoption Playbook | sf-bedrock docs
description: A practical rollout path for adopting sf-bedrock in small, reviewable steps.
eyebrow: Adoption
heading: Adoption Playbook
lede: Adopt Bedrock one useful seam at a time. Start with a testable service, prove the pattern, then expand only where the platform problem is real.
sections:
  - label: First 30 Minutes
    href: "#first-30-minutes"
  - label: First Sprint
    href: "#first-sprint"
  - label: First Production Rollout
    href: "#first-production-rollout"
  - label: Choosing The First Use Case
    href: "#choosing-the-first-use-case"
  - label: Stop Criteria
    href: "#stop-criteria"
---

## First 30 Minutes

Start with one service method that is currently hard to test because it needs
database setup. Do not begin with triggers, async orchestration, or a broad
architecture rewrite.

The smallest useful trial is:

1. Build input records with `TestData`.
2. Replace raw DML in the service with `DML`.
3. If the service consumes a record list, route that list through `Query`.
4. Add a focused test with `DMLMock` and `QueryMock`.
5. Assert the mutation or captured DML call that the service owns.

The goal of the first 30 minutes is not to adopt Bedrock. It is to prove whether
one test becomes easier to read and faster to run.

## First Sprint

For the first sprint, keep the scope boring:

- One service or one narrow automation path.
- One or two Bedrock tools.
- No public API redesign unless the service already needed it.
- No broad trigger framework migration.
- No async migration unless async pain is the reason for the pilot.

Good first-sprint outcomes are concrete:

- A slow test no longer needs database setup.
- A service's DML behavior can be asserted in memory.
- A trigger flow has one controlled place where buffered DML flushes.
- A background job has visible work records and a recovery path.

At the end of the sprint, review the code with the team that will own it. If the
pattern feels heavier than the problem, stop and choose a better use case.

## First Production Rollout

Production rollout should have an owner, a rollback path, and a small operating
surface.

Before release:

- Confirm which Bedrock source folders are included.
- Deploy the libraries the pilot uses and their required supporting metadata.
  Runtime frameworks like `Async` and `Scheduler` also need their custom
  objects, fields, custom metadata, settings, triggers, and supporting services.
- Review sharing, CRUD, and FLS boundaries using
  [Enterprise Readiness](/enterprise-readiness).
- Assign permissions for any custom objects, settings, metadata, or console
  surfaces involved.
- Run the smallest Apex tests that cover the pilot.
- Document who owns support if the pilot fails.

After release:

- Watch the behavior the pilot was meant to improve.
- For async or scheduler pilots, monitor backlog, errors, and runtime rows.
- Keep a short log of what was easier, what was confusing, and what should be
  documented before the next team adopts the pattern.

## Choosing The First Use Case

Prefer a use case with clear pain and low blast radius.

Good candidates:

- A service test that inserts many records only to exercise one branch.
- A service that performs DML and needs better assertions.
- A trigger path where related writes should be grouped and flushed once.
- A Queueable pattern that needs retry, status, and operator visibility.
- A scheduled job that should be configured from metadata instead of consuming a
  separate scheduled Apex slot.

Poor first candidates:

- A full org-wide trigger migration.
- A security-sensitive controller rewrite.
- A complex integration with unclear ownership.
- A service whose current tests are already fast and easy to understand.

## Stop Criteria

Bedrock is meant to reduce operational and cognitive load. Stop the pilot or
change direction if:

- The pattern makes production code harder for the owning team to read.
- Tests assert framework behavior instead of business behavior.
- The team cannot explain who owns production operations.
- A heavier tool is being adopted before a smaller seam has been tried.
- The problem is actually platform behavior that should be tested with real DML,
  SOQL, sharing, validation rules, or flows.

Small adoption is a feature. A team should keep only the parts that earn their
place.
