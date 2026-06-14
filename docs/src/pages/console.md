---
layout: ../layouts/DocsLayout.astro
title: Bedrock Console | sf-bedrock docs
description: A short guide to the Bedrock Console surfaces for Async and Scheduler operations.
eyebrow: Operations
heading: Bedrock Console
lede: Bedrock is code-first, but the runtime should not be invisible. The console gives operators a practical view of async work, scheduler jobs, configuration, and errors.
sections:
  - label: Overview
    href: "#overview"
  - label: Async Views
    href: "#async-views"
  - label: Scheduler Views
    href: "#scheduler-views"
  - label: How To Use It
    href: "#how-to-use-it"
  - label: Notes & Edge Cases
    href: "#notes--edge-cases"
---

![Bedrock Console Async tab showing backlog, running thread, error, and completed-today cards with Backlog, Errors, Completed, Archive, Jobs, and Settings subtabs.](/images/bedrock-console-async.png)

## Overview

The Bedrock Console is the human-facing side of Bedrock runtime frameworks. It
helps admins and developers see what async and scheduled jobs are doing after
the code has moved on.

Use it when you need to answer simple production questions:

- What work is waiting?
- What failed, and why?
- Which async job types are configured?
- Which scheduled jobs are enabled, disabled, due, or stale?

It is not a second programming model. Do not build business logic around the
console controllers. Treat the UI as an operations window over the same schema
the frameworks already use.

## Async Views

The Async console reads from `Async__c`, `Async_Archive__c`,
`Async_Job__mdt`, and `Async_Settings__c`.

| View | What it helps with |
| --- | --- |
| Dashboard | Quick counts for completed work, backlog, and errors. |
| Backlog | Pending and running work grouped by thread, class, priority, record Id, and age. |
| Errors | Failed work items with message and stack trace details. Operators can retry or delete selected errors when permissions allow it. |
| Completed | Done work items, with search and sorting for recent history. |
| Archive | Historical async work retained outside the active work table. |
| Jobs | `Async_Job__mdt` rows so teams can see configured batch sizes and job labels. |
| Settings | Runtime settings that affect async throughput and cleanup behavior. |

For day-to-day debugging, start with Errors. The stored stack trace usually tells
you whether the fix belongs in the subscriber code, the data, or the job
configuration.

## Scheduler Views

The Scheduler console reads from `Scheduler__c` and `Scheduler_Job__mdt`.

![Bedrock Console Scheduler tab showing enabled, due-now, error, and disabled cards with an upcoming jobs timeline.](/images/bedrock-console-scheduler.png)

It shows enabled and disabled jobs, jobs with errors, due jobs, next scheduled
times, last execution times, cadence labels, and whether metadata changes are
waiting for the next heartbeat.

That last bit matters. Scheduler translates metadata into runtime rows on the
heartbeat. If a config was just changed, the console can tell you when the
runtime rows should catch up.

## How To Use It

Install the console app metadata alongside the framework metadata when your
team wants operational visibility. The source lives under
`force-app/bedrock/console-app`.

Use the console to observe and recover. Use the library docs to build.

- To build record-driven background work, start with [Async](/async).
- To build recurring jobs, start with [Scheduler](/scheduler).
- To understand job records and configuration fields, read the schema tables on
  those pages.

## Notes & Edge Cases

- The console is helpful, not required. The frameworks run from Apex and
  metadata without the UI.
- Async retry and delete actions still depend on object and field permissions.
- Scheduler timing is still governed by the five-minute heartbeat. The console
  reports what Scheduler knows; it does not force a job to run.
- Console pages are operational documentation. Public Apex contracts live on
  the library pages.
