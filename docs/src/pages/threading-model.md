---
layout: ../layouts/DocsLayout.astro
title: Threading Model | sf-bedrock docs
description: Subway-style maps that explain how Bedrock Thread connects Async and the planned Event framework.
eyebrow: Start Here
heading: Threading Model
lede: Bedrock uses Thread as a shared lane and runner system. These maps show where work is stored, where a Queueable chain starts, and where to debug when a background process stalls.
sections:
  - label: Overview
    href: "#overview"
  - label: Shared Thread Map
    href: "#shared-thread-map"
  - label: Async Line
    href: "#async-line"
  - label: Event Lines
    href: "#event-lines"
  - label: Debugging With The Map
    href: "#debugging-with-the-map"
  - label: Notes & Edge Cases
    href: "#notes--edge-cases"
---

## Overview

Think of `Thread` as Bedrock's station interchange. It is not the business
framework itself. It is the shared runtime layer that gives frameworks a lane,
starts one Queueable runner for that lane, carries a `Run_Key__c`, and hands off
or recovers work when a chain ends.

`Async` is the first rider on that system. It stores record-Id work in
`Async__c` and drains it through `execute(Set<Id>)`. Event is planned as the
stateful sibling: it will store serialized payload work in `Event_Job__c` and
drain it through publication or consumption handlers.

## Shared Thread Map

The overview map shows the important boundary: Async and Event own different
work tables and semantics, but both meet at `Thread__c` and `ThreadRunner`.

![Subway-style map showing Thread as the interchange between Async, Event publication, and Event consumption work.](/images/threading-overview-subway.svg)

Use the shared map when a new developer needs to understand why `Thread__c`
exists separately from `Async__c`, or why Event should plug into the same runner
instead of creating a second lane system.

## Async Line

The Async line is record-driven. A caller gives Bedrock Ids, Bedrock writes
`Async__c` rows, and the current transaction's `Thread__c` lane drains those Ids
in configured batches.

![Subway-style map showing Async enqueue, Async work records, ThreadRunner, Async dispatcher, subscriber execution, and finalizer handoff.](/images/threading-async-subway.svg)

Use this map when a job is stuck in backlog or a team expects one large enqueue
to split into several parallel chains. Async parallelism happens between
enqueueing transactions, not inside one transaction's record set.

## Event Lines

Event has two planned lines over the same Thread station.

Reliable publication starts with a payload that should leave the org. Reliable
consumption starts with a payload that arrived and needs business handling. Both
halves use `Event_Job__c` rows, lane keys, an Event dispatcher, and finalizer
outcomes.

![Subway-style roadmap map showing Event publication and Event consumption over shared Thread lanes.](/images/threading-event-subway.svg)

Use this map while designing Event slices. Publication and consumption should be
small, inspectable halves over shared job storage and shared lane plumbing, not
one giant framework drop.

## Debugging With The Map

Start with the framework work table. For Async, inspect `Async__c`. For Event,
inspect the planned `Event_Job__c` row shape. Confirm the status, route or Apex
class, record Id or payload, retry count, and error fields.

Then inspect the lane. `Thread__c.Status__c` tells you whether a runner is
pending, active, or drained. `Pool__c` identifies the framework, `Thread_Key__c`
identifies the lane, `Run_Key__c` identifies the authorized Queueable chain, and
`Heartbeat__c` tells you whether recovery should care.

Finally, inspect the dispatcher. `ThreadRunner` selects the pool-specific
dispatcher. Async uses `Async.ThreadDispatcher`; Event should add publication
and consumption dispatchers without moving Event-specific behavior into
`Thread`.

## Notes & Edge Cases

- `Thread__c` is shared infrastructure, not a replacement for framework work
  records.
- `Async__c` remains the source of truth for Async job status.
- Event is not implemented yet; its map is an educational roadmap for the
  planned publication and consumption halves.
- The thread cap controls starts, not inserts. Work can be validly stored while
  its lane waits in `Pending`.
- A single Async enqueueing transaction creates one backlog. More threads help
  when separate transactions create separate backlogs.
