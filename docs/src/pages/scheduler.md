---
layout: ../layouts/DocsLayout.astro
title: Scheduler | sf-bedrock docs
description: A metadata-driven framework for running recordless maintenance jobs from one physical scheduled Apex job.
eyebrow: Async Services
heading: Scheduler
lede: Scheduler runs recordless maintenance work without spending one Salesforce scheduled job slot per task. One physical tick fires every five minutes, syncs metadata into runtime rows, and enqueues each due logical job as its own Queueable.
sections:
  - label: Overview
    href: "#overview"
  - label: Quickstart
    href: "#quickstart"
  - label: Examples
    href: "#examples"
  - label: Configuration
    href: "#configuration"
  - label: Testing
    href: "#testing"
  - label: How It Works
    href: "#how-it-works"
  - label: Public API
    href: "#public-api"
  - label: Notes & Edge Cases
    href: "#notes--edge-cases"
---

## Overview

`Scheduler` is for background work that has no natural record Id payload:
archive old framework rows, resume paused jobs, poll org-health state, or run
other maintenance checks. Instead of creating one Salesforce scheduled Apex job
for every logical task, Scheduler uses one physical job that wakes up every five
minutes and dispatches the logical jobs that are due.

Each logical job is an Apex class that extends `Scheduler` and overrides a
parameterless `execute()` method. The framework runs that class as a Queueable
and records `Last_Executed_At__c` plus `Last_Error__c` on its translated
`Scheduler__c` row.

**Use `Scheduler` when** you need recordless, recurring framework or org
maintenance work controlled by metadata.

**Reach for `Async` instead when** the work is tied to records and should process
a set of Ids. `Async` owns record work queues; `Scheduler` owns recurring
recordless jobs.

## Quickstart

Create a logical job by extending `Scheduler` and overriding `execute()`.

```apex
public with sharing class ArchiveAsyncJobs extends Scheduler {
    public override void execute() {
        AsyncArchiveService.archiveCompletedJobs();
    }
}
```

Create a `Scheduler_Config__mdt` record for the job:

| Field | Example |
| --- | --- |
| `DeveloperName` | `ArchiveAsyncJobs` |
| `Apex__c` | `ArchiveAsyncJobs` |
| `Is_Enabled__c` | `true` |
| `Frequency__c` | `Hours` |
| `Interval__c` | `6` |

Then schedule the physical tick once:

```apex
Id scheduledJobId = Scheduler.schedule();
```

After that, the physical job wakes up every five minutes. On each tick, it
checks whether config changed, syncs metadata into `Scheduler__c`, and enqueues
due jobs.

## Examples

### Run on every tick

Use `Every 5 Minutes` for a lightweight monitor that should run whenever the
physical scheduler wakes up.

```apex
public with sharing class ResumePausedAsyncJobs extends Scheduler {
    public override void execute() {
        LimitsResumeService.resumeWhenOrgIsHealthy();
    }
}
```

Config:

| Field | Value |
| --- | --- |
| `Apex__c` | `ResumePausedAsyncJobs` |
| `Is_Enabled__c` | `true` |
| `Frequency__c` | `Every 5 Minutes` |
| `Interval__c` | `1` |

### Run every few hours

Use `Hours` plus an interval for maintenance that should not run on every tick.

```apex
public with sharing class TrimSchedulerHistory extends Scheduler {
    public override void execute() {
        SchedulerHistoryService.trimOldRows();
    }
}
```

With `Frequency__c = Hours` and `Interval__c = 4`, the job is due when it has
never run or when `Last_Executed_At__c` is at least four hours old.

### Run every few days

Use `Days` for lower-frequency cleanup.

```apex
public with sharing class RebuildMaintenanceIndexes extends Scheduler {
    public override void execute() {
        MaintenanceIndexService.rebuild();
    }
}
```

With `Frequency__c = Days` and `Interval__c = 1`, the job is due when it has
never run or when `Last_Executed_At__c` is at least one day old.

## Configuration

Scheduler uses three metadata or runtime records.

| Type | Role |
| --- | --- |
| `Scheduler_Config__mdt` | Admin/developer-owned logical job configuration. |
| `Scheduler__c` | Runtime row translated from config, one per logical job. |
| `Scheduler_Settings__c` | Org-level settings row that stores the last metadata hash. |

`Scheduler_Config__mdt` fields:

| Field | Meaning |
| --- | --- |
| `Apex__c` | Apex class name to instantiate. The class must extend `Scheduler`. |
| `Is_Enabled__c` | Whether this logical job can run. |
| `Frequency__c` | `Every 5 Minutes`, `Hours`, or `Days`. |
| `Interval__c` | Number of hours or days. Defaults to `1` when blank or less than `1`; ignored by `Every 5 Minutes`. |

`Scheduler__c` mirrors the config fields and adds runtime state:

| Field | Meaning |
| --- | --- |
| `Config_Key__c` | The config row key, copied from `DeveloperName`. |
| `Last_Executed_At__c` | Timestamp of the last attempted run. |
| `Last_Error__c` | Last thrown error message, cleared on success. |

## Testing

Use `SchedulerMock` when testing the scheduler framework itself or code that
needs to control scheduler metadata, runtime rows, and settings in memory.

```apex
@istest static void testMaintenanceJob_runsWhenDue() {
    SchedulerMock mock = new SchedulerMock()
        .seedSettings(new Scheduler_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Metadata_Hash__c = 'same-hash'
        ))
        .job(new Scheduler__c(
            Id = new TestData.IdService().get(Scheduler__c.SObjectType),
            Config_Key__c = 'ArchiveAsyncJobs',
            Apex__c = 'ArchiveAsyncJobs',
            Is_Enabled__c = true,
            Frequency__c = Scheduler.HOURS,
            Interval__c = 6,
            Last_Executed_At__c = System.now().addHours(-6)
        ));

    Scheduler.setMock(mock);

    Test.startTest();
    Scheduler.tick();
    Test.stopTest();

    // Assert the effect of the queued job.
}
```

For logical job tests, test the subclass's `execute()` directly. That keeps the
job's business behavior separate from the scheduler dispatch mechanics.

## How It Works

Three ideas explain the Scheduler runtime.

### 1. One physical tick owns dispatch

`Scheduler.schedule()` creates one scheduled Apex job using cron expression
`0 0/5 * * * ? *`. That job runs `Scheduler.ScheduleTick`, which calls
`Scheduler.tick()`.

### 2. Metadata is translated into runtime rows

At the start of a tick, `MetadataService` reads `Scheduler_Config__mdt` and
computes a stable hash from the logical job config. If the hash changed,
`JobService.translateMetadata()` upserts matching `Scheduler__c` rows by
`Config_Key__c`. Config rows that disappeared are not deleted; their runtime rows
are disabled so history stays visible.

### 3. Due jobs are enqueued as Queueables

The tick re-queries enabled `Scheduler__c` rows after translation. Each row is
checked with `JobService.isDue(job, now)`. Due jobs are instantiated with
`Type.forName(job.Apex__c).newInstance()` and enqueued. The Queueable wrapper
records the attempted timestamp and the last error, if any.

## Public API

`Scheduler` is a `public virtual with sharing` class that implements
`Queueable`. Production code normally uses `schedule()` and subclasses
`Scheduler`.

> **A note on access modifiers:** Apex members without an access modifier are
> private. The helper methods that record execution and normalize cadence are
> implementation details.

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| `EVERY_FIVE_MINUTES` | `public static final String` | `String` | Picklist value for every physical scheduler tick. |
| `HOURS` | `public static final String` | `String` | Picklist value for hourly cadence. |
| `DAYS` | `public static final String` | `String` | Picklist value for daily cadence. |
| `tick` | `public static void tick()` | `void` | Runs one scheduler tick: sync metadata if needed, query enabled jobs, and enqueue due jobs. |
| `schedule` | `public static Id schedule()` | `Id` | Creates the physical scheduled Apex job. |
| `cron` | `public static String cron()` | `String` | Returns the five-minute cron expression. |
| `setSchedulerJob` | `public Scheduler setSchedulerJob(Id schedulerJobId)` | `Scheduler` | Sets the runtime row Id used by the Queueable wrapper to record execution. |
| `execute` | `public virtual void execute()` | `void` | Contract method. Subclasses override this with job behavior. |
| `execute` | `public void execute(QueueableContext context)` | `void` | Queueable entrypoint used by the framework. |

Important inner classes:

| Type | Description |
| --- | --- |
| `Scheduler.JobService` | Owns schedule, tick, metadata translation, due checks, and queueable enqueue. |
| `Scheduler.MetadataService` | Reads `Scheduler_Config__mdt` and computes the config hash. |
| `Scheduler.QueryService` | Reads `Scheduler__c` runtime rows through `Query.records(...)`. |
| `Scheduler.SettingsService` | Reads and writes the org default `Scheduler_Settings__c` row. |
| `Scheduler.ScheduleTick` | Physical `Schedulable` entrypoint. |
| `Scheduler.SchedulerException` | Exception used by the base contract. |

## Notes & Edge Cases

- **Overdue jobs run once, not once per missed tick.** If a two-hour job misses
  six hours of scheduler ticks, the next successful tick enqueues it one time.

- **Hourly and daily cadence is elapsed-time based.** `Hours` and `Days` compare
  `Last_Executed_At__c` to the current tick time. They are not aligned to wall
  clock boundaries like midnight or the top of the hour.

- **A new job is due immediately.** If `Last_Executed_At__c` is blank, the job is
  due on the next tick.

- **Apex class names must resolve at runtime.** `Apex__c` is passed to
  `Type.forName(...).newInstance()`. If the class does not exist or does not
  extend `Scheduler`, the tick transaction can fail before that logical job is
  enqueued.

- **Concurrency protection is not implemented yet.** The current tick attempts
  to enqueue every due enabled job. Future work may add caps or integrate with a
  shared thread/limits service.
