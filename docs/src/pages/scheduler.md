---
layout: ../layouts/DocsLayout.astro
title: Scheduler | sf-bedrock docs
description: Run all of your recurring Apex jobs from just three of your org's scheduled-job slots, on a schedule as tight as every five minutes.
eyebrow: Async Services
heading: Scheduler
lede: Salesforce caps your org at 100 scheduled Apex jobs — a limit you share with every installed package. Scheduler runs all of your recurring jobs from just three of those slots, on a schedule as tight as every five minutes. You write a class and add one metadata record; the framework handles the scheduling.
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

Sooner or later every org needs work that runs on a clock: a nightly cleanup, an
hourly sync with an outside system, a check that runs every few minutes. The
Salesforce tool for that is a scheduled Apex job — and it comes with two
squeezes.

First, **an org can hold only 100 scheduled Apex jobs at once, and that limit is
shared with every managed package you install.** Give each recurring task its
own scheduled job and a few packages can crowd you out of your own org.

Second, scheduling each job is fiddly: a `Schedulable` class wired up by hand or
a cron expression per task, and the setup screen only offers coarse preset times.

Scheduler removes both problems. It runs **every** job you write from just
**three** scheduled-job slots, no matter how many jobs you add, and it gives you
a heartbeat as tight as every five minutes. You write a class and add a metadata
record; the framework owns the scheduling. Your tenth or fiftieth job costs zero
extra slots — it is one more row of configuration.

**Use Scheduler whenever you would reach for a Salesforce scheduled job** —
anything that needs to run on a recurring cadence.

**Reach for `Async` instead when** the work is driven by records and should
process a set of Ids. `Async` runs work through record queues; Scheduler runs
jobs on a clock.

## Quickstart

Two steps: write the job, then declare it in metadata. You never schedule
anything yourself — the framework keeps its own scheduled jobs running.

**Step 1** — extend `Scheduler` and override `execute()`. This parameterless
method is the only code you write. It holds the work you want to run on a
schedule.

```apex
public with sharing class ExpireStaleQuotes extends Scheduler {
    public override void execute() {
        QuoteExpirationService.expireQuotesPastValidUntil();
    }
}
```

**Step 2** — create a `Scheduler_Config__mdt` record that points at the class and
sets how often it runs.

| Field | Example |
| --- | --- |
| `DeveloperName` | `ExpireStaleQuotes` |
| `Apex__c` | `ExpireStaleQuotes` |
| `Is_Enabled__c` | `true` |
| `Frequency__c` | `Hours` |
| `Interval__c` | `6` |

That is everything. Within five minutes the framework picks up the new record
and starts running `ExpireStaleQuotes` every six hours.

## Examples

The cadence of a job comes entirely from its `Frequency__c` and `Interval__c`.
The class never knows or cares how often it runs — keep the work in `execute()`
and let metadata decide the schedule.

### Run every five minutes

`Every 5 Minutes` runs the job each time the framework wakes up — the right
choice for time-sensitive work that should stay close to real time, like draining
an inbound integration queue.

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
| `Frequency__c` | `Every 5 Minutes` |
| `Interval__c` | `1` |

`Interval__c` is ignored for `Every 5 Minutes`; the cadence is fixed to the
five-minute heartbeat.

### Run every few hours

`Hours` plus an interval is for work that should not run on every heartbeat, like
refreshing exchange rates from an external provider.

```apex
public with sharing class RefreshExchangeRates extends Scheduler {
    public override void execute() {
        ExchangeRateService.refreshFromProvider();
    }
}
```

With `Frequency__c = Hours` and `Interval__c = 4`, the job runs when it has never
run, or when its last run was at least four hours ago.

### Run once a day

`Days` is for low-frequency work like a nightly digest email.

```apex
public with sharing class SendDailyDigest extends Scheduler {
    public override void execute() {
        DigestService.sendDailySummaryEmails();
    }
}
```

With `Frequency__c = Days` and `Interval__c = 1`, the job runs when it has never
run, or when its last run was at least a day ago.

## Configuration

You configure each job with one `Scheduler_Config__mdt` record. These are the
fields that matter:

| Field | Meaning |
| --- | --- |
| `Apex__c` | API name of the class to run. The class must extend `Scheduler`. Required. |
| `Is_Enabled__c` | Whether the job can run. Defaults to `true`. Set it to `false` to pause a job without deleting it. |
| `Frequency__c` | `Every 5 Minutes`, `Hours`, or `Days`. Defaults to `Every 5 Minutes`. |
| `Interval__c` | How many hours or days between runs. Defaults to `1`; values below `1` count as `1`; ignored by `Every 5 Minutes`. |

Configuration is the only place you set a schedule. To change how often a job
runs, edit its record — there is no Apex to redeploy and no scheduled job to
re-create. Changes take effect on the next heartbeat, within five minutes.

To watch a job in production, look at its **`Scheduler__c` runtime row**. The
framework keeps one per job and writes `Last_Executed_At__c` and `Last_Error__c`
on every run, so you can see when a job last ran and whether it failed without
digging through logs.

## Testing

Your `execute()` is plain Apex, so test it the simplest possible way: construct
the class and call it. You do not need the framework running, and you should not
test the scheduling itself — that is the framework's job, not yours.

```apex
@istest
public with sharing class StampReviewedAccountsTest {

    @istest static void testExecute_stampsReviewedAccounts() {
        List<Account> accounts = (List<Account>) new TestData(Account.sObjectType)
            .put(Account.Name, 'Acme')
            .count(3)
            .build();
        DML.insertRecords(accounts);

        new StampReviewedAccounts().execute();

        for (Account account : (List<Account>) Query.records([
            SELECT Description FROM Account
        ])) {
            Assert.areEqual('Reviewed by scheduled job', account.Description,
                'Expected the scheduled job to stamp every account it processed.');
        }
    }
}
```

If your `execute()` delegates to a service — the shape we recommend — test that
service directly, the same way you would test any other Apex. The job class then
needs nothing more than the one-line check that it calls the service.

## How It Works

Three ideas explain everything Scheduler does.

**One: three scheduled jobs, one five-minute heartbeat.** The framework keeps
three scheduled Apex jobs running. Each one fires on a fifteen-minute cycle, but
they are staggered five minutes apart, so together they wake the framework every
five minutes. That is three slots out of your hundred — fixed — no matter how
many jobs you schedule.

**Two: your jobs live in metadata, not in the schedule.** On each heartbeat the
framework reads your `Scheduler_Config__mdt` records. When that configuration has
changed, it syncs the records into one `Scheduler__c` runtime row per job; when
nothing changed, it skips the sync and moves straight to running jobs. This is
why a new or edited config record takes effect within five minutes rather than
instantly, and why you never touch a scheduled job by hand.

**Three: each due job runs as its own Queueable.** On every heartbeat the
framework checks which jobs are due — a job is due if it has never run, or if
enough time has passed since its last run — and runs each due job as a separate
Queueable with its own governor limits. After the job runs, the framework records
the time on its runtime row, and either clears the error on success or saves the
thrown message on failure.

> Cadence is measured from the last run, not from the wall clock. A daily job
> runs roughly 24 hours after it last ran — not at midnight. This keeps the model
> simple and tolerant of outages, at the cost of clock alignment.

## Public API

As a developer you touch exactly two things: the `execute()` method you override,
and the `Scheduler_Config__mdt` record that schedules it. Everything else — how
the framework schedules itself, decides what is due, and records results — is
internal, and you never call it.

### The job contract

| Member | Signature | Description |
| --- | --- | --- |
| `execute` | `public override void execute()` | The one method you write. Holds the work to run on a schedule. The base class throws if a subclass does not override it, so every job must implement it. |

### Schema

**`Scheduler_Config__mdt`** (custom metadata type) — one record per job, authored
by you. This is your control panel:

| Field | Purpose |
| --- | --- |
| `Apex__c` | API name of the `Scheduler` subclass to run. Required. |
| `Is_Enabled__c` | Whether the job can run. Defaults to `true`. |
| `Frequency__c` | `Every 5 Minutes` (default), `Hours`, or `Days`. |
| `Interval__c` | Number of hours or days between runs. Defaults to `1`. |

**`Scheduler__c`** (custom object) — one framework-owned runtime row per job. You
do not edit these; read them to see how a job is doing:

| Field | Purpose |
| --- | --- |
| `Last_Executed_At__c` | When the job last ran. |
| `Last_Error__c` | The error from the last run, or blank if it succeeded. |

## Notes & Edge Cases

- **A new job starts on the next heartbeat.** When you add or enable a config
  record, the job begins running within five minutes — not instantly.

- **Config changes take up to five minutes.** The framework re-reads
  `Scheduler_Config__mdt` once per heartbeat, so an edit applies on the next one.

- **Overdue jobs run once, not once per missed window.** If an hourly job misses
  six hours of heartbeats during an outage, it runs a single time when the
  framework recovers. There is no backfill of missed runs.

- **Hourly and daily cadence is measured from the last run.** It is not aligned to
  midnight or the top of the hour — a daily job runs about 24 hours after it last
  ran.

- **`Interval__c` is ignored for `Every 5 Minutes`.** That cadence always runs on
  the heartbeat. An interval below `1` (or left blank) counts as `1`.

- **Pause a job with `Is_Enabled__c`.** Set it to `false` to stop a job without
  losing its configuration. Deleting the config record stops the job too, but
  keeps its runtime row so its run history stays visible.

- **`Apex__c` must name a real class that extends `Scheduler`.** It is resolved by
  name at run time. If the name is wrong or the class does not extend `Scheduler`,
  the job will not run — keep the value matching your deployed class exactly.

- **Each job runs in its own Queueable.** Keep `execute()` bulk-safe and within a
  single Queueable's governor limits: query once, never run SOQL or DML inside a
  per-record loop.

- **There is no concurrency cap yet.** Every due, enabled job is run on each
  heartbeat. Limits on how many run at once are planned, not built.
