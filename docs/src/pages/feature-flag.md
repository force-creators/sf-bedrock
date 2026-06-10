---
layout: ../layouts/DocsLayout.astro
title: FeatureFlag | sf-bedrock docs
description: A tiny, cached gateway for turning Apex behavior on and off at runtime using Feature_Flag__mdt custom metadata.
eyebrow: Foundation API
heading: FeatureFlag
lede: A tiny, cached gateway for turning Apex behavior on and off at runtime. It reads boolean toggles from Feature_Flag__mdt custom metadata, fails closed when a flag is missing, and lets tests override any flag in memory — no DML required.
sections:
  - label: Overview
    href: "#overview"
  - label: Quickstart
    href: "#quickstart"
  - label: Examples
    href: "#examples"
  - label: Where Flag Values Come From
    href: "#where-flag-values-come-from"
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

`FeatureFlag` answers one question: **"is this feature turned on right now?"** You give it a flag name, it returns a `Boolean`. That single check lets you ship code that is dormant until you flip a switch, roll a feature out gradually, or keep a kill switch handy for risky behavior.

Flag values live in **`Feature_Flag__mdt` custom metadata**, so toggling a feature is a configuration change — deploy or edit a metadata record in the target org — rather than a code change. This is the classic *Feature Toggle* pattern: separate the decision to *deploy* code from the decision to *release* it.

**Use `FeatureFlag` when** you want a runtime on/off switch that admins or release engineers can control without redeploying Apex — gradual rollouts, kill switches, environment-specific behavior, or guarding work-in-progress code.

**Reach for a custom setting or your own custom metadata type instead when** you need more than a boolean. `FeatureFlag` has no percentage rollouts, no per-user or per-profile targeting, and no values beyond `true`/`false`. If you need configurable *values* (a threshold, a URL, a limit), model those directly rather than stretching a boolean toggle.

## Quickstart

Wrap new or risky behavior in an `isEnabled` check. The feature stays off until a `Feature_Flag__mdt` record with that name exists and its `Is_Enabled__c` checkbox is checked.

```apex
if (FeatureFlag.isEnabled('bedrock.feature.x')) {
    runNewBehavior();
} else {
    runLegacyBehavior();
}
```

That is the entire production API. Nothing to instantiate, no configuration object to pass.

## Examples

### Guard a feature with a simple branch

The everyday use: wrap new or risky behavior so it only runs when the flag is on.

```apex
public void processOrder(Order__c order) {
    if (FeatureFlag.isEnabled('bedrock.feature.newPricing')) {
        applyNewPricing(order);
    } else {
        applyLegacyPricing(order);
    }
}
```

### Use a flag as a kill switch

Because a missing or disabled flag returns `false`, you can wrap an entire risky code path and turn it off instantly by unchecking `Is_Enabled__c` in the org — no deployment required.

```apex
if (FeatureFlag.isEnabled('bedrock.feature.externalSync')) {
    callExternalSystem();   // disable in seconds if the integration misbehaves
}
```

### Check the same flag repeatedly without query cost

Thanks to the per-transaction cache, checking a flag inside a loop is safe. Only the first check queries; the rest are served from memory.

```apex
for (Account account : accounts) {
    if (FeatureFlag.isEnabled('bedrock.feature.enrichment')) {  // 1 query total
        enrich(account);
    }
}
```

> If you prefer, hoist the check above the loop into a local `Boolean`. Both patterns cost one query — the cache makes them equivalent — but a local variable documents that the value does not change mid-loop.

## Where Flag Values Come From

Flag values come from a single source: the **`Feature_Flag__mdt`** custom metadata type in `force-app/bedrock/lib/feature-flag/objects/`. The class queries two fields:

| Field label | API name | Type | Role |
| --- | --- | --- | --- |
| Flag Key | `Name__c` | Text (255, required, unique) | The string you pass to `isEnabled`. The query matches on this field — **not** the record's `DeveloperName` or `Label`. |
| Is Enabled | `Is_Enabled__c` | Checkbox (default `false`) | The on/off value returned by `isEnabled`. |

```apex
// The lookup the class performs (from FeatureFlag.cls)
List<Feature_Flag__mdt> flags = [
    SELECT Name__c, Is_Enabled__c
    FROM Feature_Flag__mdt
    WHERE Name__c = :name
    LIMIT 1
];
```

A few consequences worth internalizing:

- **The match is on `Name__c`, the custom "Flag Key" field.** Whatever string you store in `Name__c` is the exact string you must pass to `isEnabled`. The examples in the tests use a dotted convention like `bedrock.feature.newCheckout`, which is a readable way to namespace flags.
- **There is no hierarchy and no per-user or per-profile override.** Custom *metadata* is org-wide configuration; unlike hierarchy custom *settings*, there is no user or profile layering here. A flag is the same value for everyone in the org.
- **`Is_Enabled__c` defaults to `false`.** A newly created flag record is off until someone checks the box.
- **To change a flag in a real org**, deploy or edit the corresponding `Feature_Flag__mdt` record. No Apex redeploy is needed to flip a feature.

## Testing

Here is the problem `FeatureFlag.set` solves. Custom *metadata* records deployed to an org are visible to test methods, but you usually cannot rely on org data in a unit test — it makes tests environment-dependent, and you cannot insert new `Feature_Flag__mdt` records with DML the way you would a normal SObject. `FeatureFlag.set(name, enabled)` writes a synthetic value straight into the in-memory cache, so the very next `isEnabled(name)` call returns whatever you set — no DML, no SOQL, no dependency on what is deployed.

### Turn a flag on for a test

Even if no `Feature_Flag__mdt` record exists for the name, `set(name, true)` makes `isEnabled` return `true`.

```apex
FeatureFlag.set('bedrock.feature.newPricing', true);

Boolean enabled = FeatureFlag.isEnabled('bedrock.feature.newPricing');

Assert.areEqual(true, enabled, 'Expected set to enable a missing feature flag.');
```

### Turn a flag off for a test

Pass `false` to explicitly disable a flag — useful for asserting the legacy or "flag off" branch of your code.

```apex
FeatureFlag.set('bedrock.feature.newPricing', false);

Boolean enabled = FeatureFlag.isEnabled('bedrock.feature.newPricing');

Assert.areEqual(false, enabled, 'Expected set to explicitly disable a flag.');
```

### Test both branches of flag-guarded code

Seed the flag, exercise the unit, re-seed with the opposite value, and exercise again — all in memory.

```apex
@istest static void testProcessOrder_respectsFlagBranches() {
    OrderProcessor processor = new OrderProcessor();
    Order__c order = new Order__c();

    FeatureFlag.set('bedrock.feature.newPricing', true);
    processor.processOrder(order);
    Assert.areEqual('new', order.Pricing_Path__c, 'Expected the new pricing path when the flag is enabled.');

    FeatureFlag.set('bedrock.feature.newPricing', false);
    processor.processOrder(order);
    Assert.areEqual('legacy', order.Pricing_Path__c, 'Expected the legacy path when the flag is disabled.');
}
```

### Pass `null` to revert to the disabled default

`set(name, null)` stores a cache entry whose `Is_Enabled__c` is `null`. Because `isEnabled` evaluates `flag != null && flag.Is_Enabled__c`, a null `Is_Enabled__c` reads as `false` — so a `null` value behaves like "off," not "unknown." The entry still exists in the cache; it is not removed.

```apex
FeatureFlag.set('bedrock.feature.override', true);
FeatureFlag.set('bedrock.feature.override', null);   // reverts to disabled

Boolean enabled = FeatureFlag.isEnabled('bedrock.feature.override');

Assert.areEqual(false, enabled, 'Expected a null override to restore the default false.');
```

### Clear the cache to force a re-query

`clearCache()` is `@TestVisible`, so tests can call it to empty the entire cache — discarding both overrides set via `set` and any SOQL results cached during the test. The next `isEnabled` for any name then performs a fresh SOQL lookup.

```apex
FeatureFlag.set('bedrock.feature.cached', true);
Boolean overridden = FeatureFlag.isEnabled('bedrock.feature.cached');  // true (override)

FeatureFlag.clearCache();
Boolean restored = FeatureFlag.isEnabled('bedrock.feature.cached');    // false (re-queried, none found)

Assert.areEqual(true,  overridden, 'Override was applied while cached.');
Assert.areEqual(false, restored,   'clearCache restores the default disabled state.');
```

## How It Works

Three ideas explain everything `FeatureFlag` does.

### 1. It is a static gateway with one public read

There is nothing to instantiate. You call `FeatureFlag.isEnabled(name)` directly. Internally it looks up a `Feature_Flag__mdt` record whose `Name__c` matches the flag name and returns that record's `Is_Enabled__c` value.

### 2. It fails closed

A flag is only "on" when a matching metadata record exists **and** its `Is_Enabled__c` checkbox is `true`. Anything else returns `false`:

- The flag name is blank (`null`, `''`, or whitespace) → `false`.
- No `Feature_Flag__mdt` record matches the name → `false`.
- A record matches but `Is_Enabled__c` is `false` → `false`.

This behavior is deliberate and safe: if a flag is misspelled or its metadata was never deployed, the guarded feature stays off rather than silently turning on.

### 3. It caches per transaction

The class keeps a private static `Map<String, Feature_Flag__mdt>` named `flagsByName`. The first time you ask about a flag, it runs one SOQL query and stores the result — *including a `null` entry* when no record was found. Every later read of the same name in the same transaction returns the cached value with no further query.

Because `static` state in Apex lives for the duration of a single transaction, the cache is naturally scoped to one execution context and starts empty in the next one.

> **Why caching a `null` matters:** when a flag has no metadata record, `FeatureFlag` still writes a `null` entry for that name. A missing flag therefore costs *one* query per transaction, not one query per check. Checking an undefined flag a thousand times in a loop is still a single SOQL call.

## Public API

`FeatureFlag` is a `public inherited sharing` class. Only **two** members are callable from production code; the rest are private implementation details.

> **A note on access modifiers:** in Apex, a member with **no** access modifier is `private`. Two methods in this class — `get(String name)` and `clearCache()` — have no `public` modifier, making them private. `clearCache` is annotated `@TestVisible`, which exposes it to test classes only; it remains private to all other callers.

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| `isEnabled` | `public static Boolean isEnabled(String name)` | `Boolean` | The one method production code should call. Returns `true` only when a `Feature_Flag__mdt` record with `Name__c = name` exists and its `Is_Enabled__c` is `true`. Returns `false` for blank names and missing flags (fail closed). |
| `set` | `@TestVisible public static void set(String name, Boolean enabled)` | `void` | Writes a flag value directly into the in-memory cache, overriding or pre-seeding what `isEnabled` will return for `name` in the current transaction. Intended for tests only — see [Testing](#testing). |

### Public properties

**There are none.** `FeatureFlag` exposes no public properties or public fields. Its only state is the private static cache `flagsByName`, which you interact with exclusively through the methods above.

### Private members (for context, not for calling)

| Member | Visibility | Role |
| --- | --- | --- |
| `flagsByName` | `private static` | The per-transaction cache of `Name__c` → `Feature_Flag__mdt` (or `null`). |
| `get(String name)` | `private static` | Cache-aware lookup: returns the cached entry if present, otherwise runs the SOQL query and caches the result (including `null` when no record is found). |
| `clearCache()` | `private static`, `@TestVisible` | Empties the entire cache. Reachable from test code only; lets a test discard all overrides and cached SOQL results so the next read re-queries. |

## Notes & Edge Cases

- **No access modifier means private.** Only `isEnabled` and `set` are callable from production code. `get` and `clearCache` are private; `clearCache` is reachable only from test code via `@TestVisible`. Do not build production logic against them.

- **Match on `Name__c`, not `DeveloperName`.** The query filters on the custom "Flag Key" field. The string in `Name__c` must equal the string you pass to `isEnabled` exactly — including case and any dotted namespace prefix.

- **Fail closed is a feature, not a bug.** A misspelled name, a flag whose metadata was never deployed, and a blank name all return `false`. Guarded features stay off until a real, enabled record exists. Double-check spelling if a flag will not turn on.

- **The cache is per transaction.** Values are stored in static state, which lives for one Apex transaction. A `Feature_Flag__mdt` record changed mid-transaction (or deployed at that moment) is not reflected until the next transaction. In tests, use `clearCache()` to force a fresh read.

- **`set(name, null)` reads as disabled, not absent.** It stores a `Feature_Flag__mdt` with `Is_Enabled__c = null` in the cache. The entry is not removed, so subsequent calls do not re-query. Because `isEnabled` evaluates `flag != null && flag.Is_Enabled__c`, a null `Is_Enabled__c` returns `false`.

- **`set` only affects the current transaction's memory.** It does not insert metadata and does not persist anywhere. It is purely a test seam for the in-memory cache. Do not call it from production code expecting durable configuration.

- **Seed flags in tests; do not rely on org data.** Use `FeatureFlag.set` to put the flag into a known state so your test is deterministic regardless of which `Feature_Flag__mdt` records happen to be deployed in the running org.

- **It is a boolean toggle only.** No percentages, no per-user or per-profile targeting, no non-boolean values. If you outgrow on/off, model the need with a custom setting or a richer custom metadata type rather than stretching `FeatureFlag`.
