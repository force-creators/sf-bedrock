---
layout: ../layouts/DocsLayout.astro
title: Why Bedrock | sf-bedrock docs
description: Why sf-bedrock exists, what it optimizes for, and how it helps Salesforce teams adopt enterprise-safe Apex without heavy ceremony.
eyebrow: Adoption
heading: Why Bedrock
lede: Bedrock is for Salesforce teams that need enterprise-safe automation without making everyday Apex hard to read, debug, or test.
sections:
  - label: The Problem
    href: "#the-problem"
  - label: What Bedrock Optimizes For
    href: "#what-bedrock-optimizes-for"
  - label: What Bedrock Is Not
    href: "#what-bedrock-is-not"
  - label: Battle-Tested Roots
    href: "#battle-tested-roots"
  - label: Adoption Promise
    href: "#adoption-promise"
---

## The Problem

Salesforce automation gets difficult when scale, tests, and operations collide.
Triggers call services, services write records, those writes start more
automation, and async work disappears into Queueable chains that are hard to
observe. Tests become slow because they need database setup just to prove a
service changed a field or tried to save a record.

Enterprise Apex frameworks can solve parts of that problem, but many make a new
one: the framework becomes harder to understand than the business code. Bedrock
takes a smaller path. It gives teams focused seams for DML, query results, test
data, trigger coordination, record buffering, scheduling, and async work without
asking every developer to learn a large framework vocabulary first.

## What Bedrock Optimizes For

Bedrock optimizes for ordinary Salesforce engineers who need code they can
trust under pressure:

- **Readable production Apex.** Business code should still look like Apex, not a
  framework exercise.
- **Fast, meaningful tests.** Unit tests should prove mutations, calls, and
  decisions without inserting records just to reach the code under test.
- **Small seams.** DML, query results, cache, and async work should be mockable
  without pulling an entire architecture into every class.
- **Visible background work.** Async jobs should have records, statuses, retry
  behavior, and operational recovery paths.
- **Incremental adoption.** A team should be able to adopt one tool in one
  service before deciding whether the rest belongs in the org.

## What Bedrock Is Not

Bedrock is not a replacement for every architecture decision in a Salesforce
org. It does not try to be an ORM, a selector generator, a packaging system, a
security engine, or a complete application framework.

It also does not remove the need for Salesforce judgment. Teams still need to
choose sharing keywords deliberately, enforce CRUD and FLS where their
application boundary requires it, design selectors and services, and decide what
belongs in synchronous automation versus background work.

Bedrock's job is to make the common safe path easier, smaller, and more
inspectable.

## Battle-Tested Roots

Bedrock is built from patterns shaped in Fortune 100-scale Salesforce
environments, then refined into a smaller, inspectable framework for teams that
want enterprise safety without heavy ceremony.

That origin matters, but it should not be confused with public benchmark claims.
The current public documentation should describe the design intent, operating
boundaries, and recommended rollout path clearly. When public measurements are
available, they can be added as evidence. Until then, the honest claim is that
Bedrock comes from large-org automation problems: governor limits, async fan-out,
test speed, trigger hygiene, and operational recovery.

## Adoption Promise

Bedrock should never require an all-or-nothing rewrite. The preferred adoption
path is small:

1. Pick one service that is painful to test.
2. Route writes through `DML`, route controlled record lists through `Query`, and
   build records with `TestData`.
3. Prove that the test became faster and easier to understand.
4. Add heavier tools like `RecordBuffer`, `TriggerHandler`, `Async`, or
   `Scheduler` only when the problem needs them.

That is the core promise: enterprise-safe patterns that can enter the org one
clear win at a time.
