---
layout: ../layouts/DocsLayout.astro
title: Limiter | sf-bedrock docs
description: A small org-health utility that exposes current transaction and platform limits, then checks specific limits against a threshold.
eyebrow: Other
heading: Limiter
lede: Limiter reports current transaction and org/platform limit usage in one place. Use it in subscriber Apex before starting work that should wait when the org is near a limit.
sections:
  - label: Overview
    href: "#overview"
  - label: Quickstart
    href: "#quickstart"
  - label: Examples
    href: "#examples"
  - label: Known Limit Types
    href: "#known-limit-types"
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

`Limiter` gives subscriber code a single place to read limit usage and answer one
small question: is this specific limit still below the threshold I care about?
It covers transaction limits from `Limits` and org/platform limits from
`OrgLimits`.

**Use `Limiter` when** subscriber Apex needs to decide whether to start more
work. Common cases include queueable launch checks, platform event publish
checks, API-sensitive work, and any place where subscriber settings own the
threshold.

**Reach for Salesforce `Limits` or `OrgLimits` directly when** you only need one
raw counter in a private local method and do not need a shared Bedrock dependency
or a mockable seam.

## Quickstart

Check a known limit against a subscriber-provided threshold:

```apex
Decimal thresholdPercent = 80;

if (!Limiter.isSafe(Limiter.types.DAILY_ASYNC_APEX_EXECUTIONS, thresholdPercent)) {
    return;
}

System.enqueueJob(new RebuildSearchIndexJob());
```

Read a specific limit when you need the numbers:

```apex
Limiter.LimitUsage usage = Limiter.getLimit(Limiter.types.QUEUEABLE_JOBS);

if (usage != null) {
    System.debug('Queueable jobs used: ' + usage.used + ' of ' + usage.allowed);
}
```

## Examples

### Gate queueable work

Use `isSafe(type, thresholdPercent)` when subscriber code owns the setting and only
needs a yes/no answer.

```apex
public inherited sharing class SubscriberWorkLauncher {
    public static void launch() {
        Decimal thresholdPercent = 85;

        if (!Limiter.isSafe(Limiter.types.DAILY_ASYNC_APEX_EXECUTIONS, thresholdPercent)) {
            return;
        }

        System.enqueueJob(new ProcessPendingWorkJob());
    }
}
```

### Inspect one limit

`getLimit(type)` returns a `Limiter.LimitUsage` object with the limit name,
current usage, allowed amount, remaining capacity, and usage ratio.

```apex
Limiter.LimitUsage usage = Limiter.getLimit(Limiter.types.DAILY_STANDARD_VOLUME_PLATFORM_EVENTS);

if (usage != null && usage.remaining > 0) {
    System.debug('Platform event publishes remaining: ' + usage.remaining);
}
```

### Read all available limits

`getLimits()` returns a map keyed by limit name. The map includes Bedrock's known
transaction limit names and the names returned by Salesforce `OrgLimits`.

```apex
Map<String, Limiter.LimitUsage> limitsByName = Limiter.getLimits();

for (String name : limitsByName.keySet()) {
    Limiter.LimitUsage usage = limitsByName.get(name);
    System.debug(name + ': ' + usage.ratio);
}
```

### Use a raw OrgLimits key

The enum covers known Bedrock-friendly names. If Salesforce exposes an
`OrgLimits` key that is not represented in `Limiter.types`, use the string
overload.

```apex
if (!Limiter.isSafe('DailyApiRequests', 90)) {
    return;
}
```

## Known Limit Types

Use `Limiter.types` when you do not want magic strings in subscriber code.

| Type | Salesforce key |
| --- | --- |
| `QUEUEABLE_JOBS` | `QueueableJobs` |
| `SOQL_QUERIES` | `SOQLQueries` |
| `CPU_TIME` | `CPUTime` |
| `HEAP_SIZE` | `HeapSize` |
| `DML_STATEMENTS` | `DMLStatements` |
| `DAILY_ASYNC_APEX_EXECUTIONS` | `DailyAsyncApexExecutions` |
| `DAILY_STANDARD_VOLUME_PLATFORM_EVENTS` | `DailyStandardVolumePlatformEvents` |

## Testing

Use `LimiterMock` to seed only the limits a test cares about. The mock extends
`Limiter.Service`, so tests can install it with the `@testVisible` `setMock`
hook.

```apex
@istest static void launch_skipsWorkWhenDailyAsyncIsAtThreshold() {
    Limiter.setMock(new LimiterMock()
        .setLimit(Limiter.types.DAILY_ASYNC_APEX_EXECUTIONS, 90, 100));

    Boolean isSafe = Limiter.isSafe(Limiter.types.DAILY_ASYNC_APEX_EXECUTIONS);

    Assert.isFalse(isSafe,
        'Expected daily async usage at the default threshold to be unsafe.');
}
```

The mock also accepts a raw limit name when a test needs a Salesforce key that
is not in `Limiter.types`.

```apex
@istest static void apiGate_usesRawOrgLimitName() {
    Limiter.setMock(new LimiterMock()
        .setLimit('DailyApiRequests', 75, 100));

    Assert.isTrue(Limiter.isSafe('DailyApiRequests', 80),
        'Expected API usage below the configured threshold to be safe.');
}
```

## How It Works

Three ideas explain everything `Limiter` does.

### 1. Gather transaction limits

`Limiter.Service.getLimits()` adds transaction usage for queueable jobs, SOQL
queries, CPU time, heap size, and DML statements by reading the Salesforce
`Limits` class.

### 2. Add Salesforce org/platform limits

The same method loops over `OrgLimits.getMap().values()` and adds every
Salesforce-provided org limit to the result map. This is how callers can inspect
daily async, platform event, API, storage, and other org-level counters without
`Limiter` hard-coding every possible limit key.

### 3. Compare one limit to one threshold

`isSafe(name, thresholdPercent)` reads one limit and compares its `ratio` to the
threshold. The threshold is a percent, so `80` means "unsafe at 80 percent or
higher." Subscriber code owns threshold configuration and passes the value in.

> `Limiter` intentionally checks one named limit at a time. It reports capacity;
> it does not decide which limits matter to a subscriber's own service.

## Public API

`Limiter` is declared `public virtual inherited sharing`. It exposes static
facade methods backed by an injectable nested `Service`.

> **A note on access modifiers:** Apex members with no access modifier are
> private. The singleton `instance`, the `add(...)` helper, and the
> `@testVisible setMock(...)` hook are intentionally not public API.

### Static Methods

| Method | Signature | Returns | Description |
| --- | --- | --- | --- |
| `getLimits` | `getLimits()` | `Map<String, Limiter.LimitUsage>` | Returns all tracked transaction and org/platform limits keyed by limit name. |
| `getLimit` | `getLimit(String name)` | `Limiter.LimitUsage` | Returns one tracked limit by raw name, or `null` when the name is not present. |
| `getLimit` | `getLimit(Limiter.types name)` | `Limiter.LimitUsage` | Returns one tracked known limit by enum value. |
| `isSafe` | `isSafe(String name)` | `Boolean` | Checks one raw named limit against the default 90 percent threshold. |
| `isSafe` | `isSafe(String name, Decimal thresholdPercent)` | `Boolean` | Checks one raw named limit against the caller-provided threshold. |
| `isSafe` | `isSafe(Limiter.types name)` | `Boolean` | Checks one known limit against the default 90 percent threshold. |
| `isSafe` | `isSafe(Limiter.types name, Decimal thresholdPercent)` | `Boolean` | Checks one known limit against the caller-provided threshold. |
| `key` | `key(Limiter.types name)` | `String` | Returns the Salesforce key used for a known enum value. |

### Inner Types

| Type | Members | Description |
| --- | --- | --- |
| `Limiter.LimitUsage` | `name`, `used`, `allowed`, `remaining`, `ratio` | A single limit's current usage. `ratio` is `used / allowed`, or `0` when allowed is blank or zero. |
| `Limiter.types` | `QUEUEABLE_JOBS`, `SOQL_QUERIES`, `CPU_TIME`, `HEAP_SIZE`, `DML_STATEMENTS`, `DAILY_ASYNC_APEX_EXECUTIONS`, `DAILY_STANDARD_VOLUME_PLATFORM_EVENTS` | Known limit keys with enum overloads for `getLimit` and `isSafe`. |
| `Limiter.Service` | `getLimits`, `getLimit`, `isSafe` | Injectable implementation used by the static facade. |

### Test Helper

| Class | Method | Description |
| --- | --- | --- |
| `LimiterMock` | `setLimit(String name, Integer used, Integer allowed)` | Seeds a raw named limit for tests. |
| `LimiterMock` | `setLimit(Limiter.types name, Integer used, Integer allowed)` | Seeds a known enum limit for tests. |
| `LimiterMock` | `limits(Map<String, Limiter.LimitUsage> currentLimits)` | Replaces the mock's full limits map. |

## Notes & Edge Cases

- **Thresholds are subscriber-owned.** `Limiter` has a 90 percent default for the
  no-threshold overloads, but subscriber settings should pass an explicit
  threshold when the decision is configurable.

- **Missing names are unsafe for checks.** `getLimit(name)` returns `null` when a
  name is not present. `isSafe(name, thresholdPercent)` returns false for a
  missing name so bad call sites fail closed.

- **`Limiter.types` is not exhaustive.** Salesforce can expose more `OrgLimits`
  names than the enum currently models. Use the string overload for those names.

- **The ratio is a decimal from 0 to 1.** A 75 percent used limit has
  `ratio = 0.75`. The threshold argument is a percent, so pass `75`, not `0.75`.

- **Limiter only reports and checks usage.** Subscriber code decides what to do
  when a limit is unsafe.
