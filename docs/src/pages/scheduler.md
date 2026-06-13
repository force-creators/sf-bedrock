---
layout: ../layouts/DocsLayout.astro
title: Scheduler | sf-bedrock docs
description: Run recurring Apex jobs from a fixed set of scheduled-job slots, with logical jobs configured in custom metadata.
eyebrow: Async Services
heading: Scheduler
lede: Salesforce scheduled Apex slots are shared across your org and installed packages. Scheduler gives you one Bedrock heartbeat every five minutes, then runs your logical jobs from metadata when they are due.
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

Use `Scheduler` for Apex work that runs on a clock: retrying integrations,
cleaning old rows, refreshing cached data, sending digests, or checking for work
that should happen every few minutes.

Salesforce scheduled Apex works, but each scheduled job consumes one of your
org's 100 scheduled-job slots. That limit is shared with installed packages. A
large org can run out faster than you expect.

`Scheduler` keeps the scheduled Apex footprint fixed. Bedrock creates twelve
physical scheduled jobs, one for each five-minute mark in the hour. Those jobs
all call the same top-level `SchedulerTick` entrypoint. On each tick, the
framework reads your logical job configuration and enqueues only the jobs that
are due.

**Use `Scheduler` when** the work is time-based and should run repeatedly.

**Reach for `Async` instead when** the work starts from records and should
process a set of Ids. `Async` owns queued record work. `Scheduler` owns recurring
clock-based work.

## Quickstart

There are three pieces: write the job, configure the job, and install the
Bedrock heartbeat once.

**Step 1** - extend `Scheduler` and override `execute()`.

```apex
public with sharing class ExpireStaleQuotes extends Scheduler {
    public override void execute() {
        QuoteExpirationService.expireQuotesPastValidUntil();
    }
}
```

**Step 2** - create a `Scheduler_Config__mdt` record.

| Field | Example |
| --- | --- |
| `DeveloperName` | `ExpireStaleQuotes` |
| `Apex__c` | `ExpireStaleQuotes` |
| `Is_Enabled__c` | `true` |
| `Frequency__c` | `Hours` |
| `Frequency_Value__c` | `6` |

That means: run `ExpireStaleQuotes` about every six hours.

**Step 3** - schedule the Bedrock heartbeat once.

```apex
Scheduler.schedule();
```

`Scheduler.schedule()` creates twelve physical scheduled Apex jobs named
`Bedrock Scheduler 00`, `Bedrock Scheduler 05`, and so on through
`Bedrock Scheduler 55`. Re-running it replaces existing Bedrock scheduler jobs
before creating the current set.

## Examples

The class does not know how often it runs. Keep the work in `execute()` and let
metadata control the cadence.

### Run every five minutes

Use `Minutes` for work that should stay close to real time, like draining an
integration retry queue.

```apex
public with sharing class RetryFailedCallouts extends Scheduler {
    public override void execute() {
        IntegrationRetryService.retryPendingCallouts();
    }
}
```

Config:

| Field | Value |
| --- | --- |
| `Apex__c` | `RetryFailedCallouts` |
| `Is_Enabled__c` | `true` |
| `Frequency__c` | `Minutes` |
| `Frequency_Value__c` | `5` |

Minute values are limited to five-minute increments: `5`, `10`, `15`, through
`55`.

### Run every few hours

Use `Hours` for work that should run during the day, but not on every heartbeat.

```apex
public with sharing class RefreshExchangeRates extends Scheduler {
    public override void execute() {
        ExchangeRateService.refreshFromProvider();
    }
}
```

With `Frequency__c = Hours` and `Frequency_Value__c = 4`, the job runs when it
has never run, or when its last run was at least four hours ago.

### Run every day

Use `Days` for lower-frequency maintenance, reporting, or digest work.

```apex
public with sharing class SendDailyDigest extends Scheduler {
    public override void execute() {
        DigestService.sendDailySummaryEmails();
    }
}
```

With `Frequency__c = Days` and `Frequency_Value__c = 1`, the job runs when it
has never run, or when its last run was at least a day ago.

## Configuration

Each logical job has one `Scheduler_Config__mdt` record.

| Field | Meaning |
| --- | --- |
| `Apex__c` | API name of the class to run. The class must extend `Scheduler`. Required. |
| `Is_Enabled__c` | Whether the job can run. Defaults to `true`. Set it to `false` to pause a job. |
| `Frequency__c` | Cadence unit. Supported values are `Minutes`, `Hours`, and `Days`. Blank values are treated as `Minutes`. |
| `Frequency_Value__c` | Cadence amount. For `Minutes`, choose `5`, `10`, `15`, through `55`. For `Hours` and `Days`, choose `1` through `55`. |

`Interval__c` is legacy metadata. Current Scheduler code reads
`Frequency_Value__c` instead.

To change how often a job runs, edit the metadata record. There is no job class
to redeploy and no per-job scheduled Apex record to recreate. The change applies
on the next five-minute heartbeat.

To check production status, read the job's `Scheduler__c` runtime row. Scheduler
writes `Last_Executed_At__c` when a heartbeat enqueues the job. The Queueable
then clears or writes `Last_Error__c` depending on the result.

## Testing

Most job tests should not involve the scheduler framework. Your job is plain
Apex, so construct it and call `execute()`.

```apex
@istest
public with sharing class StampReviewedAccountsTest {

    @istest static void testExecute_stampsReviewedAccounts() {
        List<Account> accounts = (List<Account>) new TestData(Account.sObjectType)
            .put(Account.Name, 'Acme')
            .mockIds()
            .count(3)
            .build();

        StampReviewedAccounts.ReviewService service = new StampReviewedAccounts.ReviewService();
        service.review(accounts);

        for (Account account : accounts) {
            Assert.areEqual(
                'Reviewed by scheduled job',
                account.Description,
                'Expected the scheduled job service to stamp each account it processed.'
            );
        }
    }
}
```

If the job delegates to a service, test the service directly. Keep the scheduled
job class thin enough that it does not need much of its own coverage.

## How It Works

Three ideas explain everything `Scheduler` does.

**One: twelve scheduled jobs, one five-minute heartbeat.** `Scheduler.schedule()`
creates a top-level `SchedulerTick` scheduled job at each five-minute mark in the
hour. Salesforce sees twelve scheduled Apex jobs. Bedrock sees one heartbeat.

**Two: logical jobs live in metadata.** On each heartbeat, Scheduler checks
`Scheduler_Config__mdt`. If the metadata hash changed, it translates those
records into `Scheduler__c` runtime rows. Removed metadata records are disabled,
not deleted, so their run history stays visible.

**Three: each due logical job runs as its own Queueable.** A job is due when it
has never run, or when enough time has passed since `Last_Executed_At__c`.
Scheduler records the heartbeat attempt time before it enqueues each due job.
After the Queueable finishes, it either clears `Last_Error__c` or stores the
thrown message. A Queueable Finalizer also records unhandled queueable failures,
such as governor limit exceptions that cannot be caught by normal Apex
`try/catch`.

> Cadence is measured from the last scheduler attempt, not from Queueable start
> time or from the wall clock. A daily job runs roughly 24 hours after its last
> scheduler attempt. It does not align itself to midnight.

## Public API

Most app code touches only one method: the `execute()` override in your
`Scheduler` subclass. Setup code may call `Scheduler.schedule()` to install the
heartbeat.

### Job contract

| Member | Signature | Description |
| --- | --- | --- |
| `execute` | `public override void execute()` | Holds the scheduled work. The base implementation throws, so each job must override it. |

### Setup methods

| Member | Signature | Description |
| --- | --- | --- |
| `schedule` | `public static void schedule()` | Replaces existing `Bedrock Scheduler %` scheduled jobs and creates twelve five-minute `SchedulerTick` jobs. |
| `tick` | `public static void tick()` | Runs one scheduler heartbeat. Usually called by `SchedulerTick`, not application code. |

### Schedulable entrypoint

| Class | Signature | Description |
| --- | --- | --- |
| `SchedulerTick` | `public with sharing class SchedulerTick implements Schedulable` | Top-level scheduled Apex class used by the physical Bedrock heartbeat jobs. It delegates to `Scheduler.tick()`. |

### Schema

**`Scheduler_Config__mdt`** is one metadata record per logical job.

| Field | Purpose |
| --- | --- |
| `Apex__c` | API name of the `Scheduler` subclass to run. Required. |
| `Is_Enabled__c` | Whether the job can run. Defaults to `true`. |
| `Frequency__c` | Cadence unit: `Minutes`, `Hours`, or `Days`. |
| `Frequency_Value__c` | Cadence amount. Minute values are five-minute increments from `5` through `55`; hour and day values are `1` through `55`. |
| `Interval__c` | Legacy field retained for compatibility. Current Scheduler code does not read it. |

**`Scheduler__c`** is one runtime row per logical job. Scheduler owns these rows.

| Field | Purpose |
| --- | --- |
| `Config_Key__c` | Metadata `DeveloperName` for the source config record. |
| `Apex__c` | Class name copied from metadata. |
| `Is_Enabled__c` | Runtime enabled flag copied from metadata. |
| `Frequency__c` | Runtime cadence unit copied from metadata. |
| `Frequency_Value__c` | Runtime cadence amount copied from metadata. |
| `Metadata_Hash__c` | Internal hash of the metadata state that produced the runtime row. |
| `Last_Executed_At__c` | Last attempted run time. |
| `Last_Error__c` | Last error message, or blank after a successful run. |

## Notes & Edge Cases

- **A new job starts on the next heartbeat.** New and edited config records are
  picked up within about five minutes.

- **Minute cadences are five-minute increments.** Use `Minutes` with
  `Frequency_Value__c = 5` for the fastest cadence.

- **Overdue jobs run once.** Scheduler does not replay every missed window after
  an outage. If a daily job missed three days, it runs once on the next
  successful heartbeat.

- **Cadence is measured from the last attempt.** Hourly and daily jobs are not
  aligned to the top of the hour or midnight. Queueable start delay does not
  push the next due window later.

- **A bad job row does not stop the whole tick.** If `Apex__c` names a missing
  class or something that cannot be enqueued as a `Scheduler`, Scheduler records
  the error on that row and continues to the next due job.

- **Unhandled queueable failures are recorded by a finalizer.** If a scheduler
  job fails in a way normal Apex cannot catch, Scheduler still updates
  `Last_Error__c` from the finalizer transaction.

- **Each job runs in its own Queueable.** Keep `execute()` bulk-safe and within a
  single Queueable's governor limits. Query once. Do not put SOQL or DML inside
  a per-record loop.

- **There is no concurrency cap yet.** Every enabled, due job is enqueued on each
  heartbeat. Limits on how many jobs run at once are planned, not built.
