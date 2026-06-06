---
layout: ../layouts/DocsLayout.astro
title: FeatureFlag | sf-bedrock docs
description: Technical documentation and usage examples for the sf-bedrock FeatureFlag Apex utility.
eyebrow: Foundation API
heading: FeatureFlag
lede: A tiny, cached gateway for turning Apex behavior on and off at runtime. It reads boolean toggles from Feature_Flag__mdt custom metadata, fails closed when a flag is missing, and lets tests override any flag in memory — no DML required.
sections:
  - label: Purpose
    href: "#purpose"
  - label: How It Works
    href: "#how-it-works"
  - label: Where Flag Values Come From
    href: "#where-flag-values-come-from"
  - label: Public API
    href: "#public-api"
  - label: Examples
    href: "#examples"
  - label: Setting Flags In Tests
    href: "#setting-flags-in-tests"
  - label: Gotchas & Testing Notes
    href: "#gotchas-and-testing-notes"
---

## Purpose

`FeatureFlag` is a small static utility that answers one question:
**"is this feature turned on right now?"** You give it a flag name, it returns a
`Boolean`. That single check lets you ship code that is dormant until you flip a
switch, roll a feature out gradually, or keep a kill switch handy for risky
behavior.

```apex
if (FeatureFlag.isEnabled('bedrock.feature.newCheckout')) {
  runNewCheckout();
} else {
  runLegacyCheckout();
}
```

The flag values live in **`Feature_Flag__mdt` custom metadata**, so toggling a
feature is a configuration change (deploy a metadata record, or edit it in the
target org) rather than a code change. This is the classic *Feature Toggle*
pattern: separate the decision to *deploy* code from the decision to *release*
it.

**Use `FeatureFlag` when** you want a runtime on/off switch that admins or
release engineers can control without redeploying Apex — gradual rollouts, kill
switches, environment-specific behavior, or guarding work-in-progress code.

**Reach for something else when** you need more than a boolean. `FeatureFlag`
has no percentage rollouts, no per-user or per-profile targeting, no values
beyond `true`/`false`. If you need configurable *values* (a threshold, a URL, a
limit), use a custom setting or your own custom metadata type instead.

## How It Works

Three ideas explain everything `FeatureFlag` does.

### 1. It is a static gateway with one public read

There is nothing to instantiate. You call `FeatureFlag.isEnabled(name)`
directly. Internally it looks up a `Feature_Flag__mdt` record whose `Name__c`
matches your flag name and returns that record's `Is_Enabled__c` value.

### 2. It fails closed

A flag is only "on" when a matching metadata record exists **and** its
`Is_Enabled__c` checkbox is `true`. Anything else returns `false`:

- The flag name is blank (`null`, `''`, or whitespace) → `false`.
- No `Feature_Flag__mdt` record matches the name → `false`.
- A record matches but `Is_Enabled__c` is `false` → `false`.

```apex
// from FeatureFlag.cls
public static Boolean isEnabled(String name) {
    if (String.isBlank(name)) return false;

    Feature_Flag__mdt flag = get(name);
    return flag != null && flag.Is_Enabled__c;
}
```

This "fail closed" behavior is deliberate and safe: if a flag is misspelled or
its metadata was never deployed, the guarded feature stays **off** rather than
silently turning on.

### 3. It caches per transaction

The class keeps a private static `Map<String, Feature_Flag__mdt>`
(`flagsByName`). The first time you ask about a flag, it runs one SOQL query and
stores the result — *including a `null`* when no record was found. Every later
read of the same name in the same transaction returns the cached value and runs
**no further query**.

```apex
// First call for this name → 1 SOQL query, result cached
Boolean a = FeatureFlag.isEnabled('bedrock.feature.x');
// Second call for the same name → served from cache, 0 queries
Boolean b = FeatureFlag.isEnabled('bedrock.feature.x');
```

Because `static` state in Apex lives for the duration of a single transaction,
the cache is naturally scoped to one execution context and starts empty in the
next one. This is the *Memoization* pattern — compute once, reuse the result —
and it keeps `FeatureFlag` cheap to call even inside loops.

> **Why caching a `null` matters:** when a flag has no metadata record,
> `FeatureFlag` still caches the `null` lookup. That means a missing flag costs
> *one* query per transaction, not one query per check. Checking an undefined
> flag a thousand times in a loop is still a single SOQL call.

## Where Flag Values Come From

Flag values come from a single source: the **`Feature_Flag__mdt`** custom
metadata type in `force-app/bedrock/lib/feature-flag/objects/`. The class queries
two fields:

| Field | API name | Type | Role |
| --- | --- | --- | --- |
| Flag Key | `Name__c` | Text (255, required, unique) | The string you pass to `isEnabled`. This is what the query matches on — **not** the record's `DeveloperName`/`Label`. |
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

- **The match is on `Name__c`, the custom "Flag Key" field.** Whatever string
  you store in `Name__c` is the exact string you must pass to `isEnabled`. The
  examples in the tests use a dotted convention like
  `bedrock.feature.newCheckout`, which is a readable way to namespace flags.
- **There is no hierarchy and no per-user/per-profile override.** Custom
  *metadata* is org-wide configuration; unlike hierarchy custom *settings*,
  there is no user/profile layering here. A flag is the same value for everyone
  in the org.
- **`Is_Enabled__c` defaults to `false`.** A newly created flag record is off
  until someone checks the box.
- **To change a flag in a real org**, deploy or edit the corresponding
  `Feature_Flag__mdt` record. No Apex redeploy is needed to flip a feature.

## Public API

`FeatureFlag` is a `public inherited sharing` class. Despite being a short file,
only **two** members are genuinely callable from your code; the rest are private
implementation details.

> **A note on access modifiers:** in Apex, a member with **no** access modifier
> is `private`. Two methods in this class —`get(...)` and `clearCache()`— have no
> `public` modifier, so they are not part of the supported surface. `clearCache`
> is annotated `@TestVisible`, which exposes it to test classes *only*; it is
> still private to ordinary callers.

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| `isEnabled` | `isEnabled(String name)` | `Boolean` | The one method production code should call. Returns `true` only when a `Feature_Flag__mdt` record with `Name__c = name` exists and its `Is_Enabled__c` is `true`. Returns `false` for blank names and missing flags (fail closed). |
| `set` | `set(String name, Boolean enabled)` | `void` | `@TestVisible public static`. Writes a flag value directly into the in-memory cache, overriding (or pre-seeding) what `isEnabled` will return for `name` in the current transaction. Intended for tests — see [Setting Flags In Tests](#setting-flags-in-tests). |

### Public properties

**There are none.** `FeatureFlag` exposes no public properties or public fields.
Its only state is the private static cache `flagsByName`, which you interact with
exclusively through the methods above.

### Private members (for context, not for calling)

Knowing what is *not* public makes the behavior predictable:

| Member | Visibility | Role |
| --- | --- | --- |
| `flagsByName` | `private static` | The per-transaction cache of `Name__c` → `Feature_Flag__mdt` (or `null`). |
| `get(String name)` | `private static` | Cache-aware lookup: returns the cached record if present, otherwise runs the SOQL query and caches the result (including `null`). |
| `clearCache()` | `private static`, `@TestVisible` | Empties the cache. Visible to tests only; lets a test discard overrides and cached lookups so the next read re-queries. |

## Examples

### Guard a feature with a simple branch

The everyday use: wrap new or risky behavior in an `isEnabled` check so it only
runs when the flag is on.

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

Because a missing or disabled flag returns `false`, you can wrap an entire risky
code path and turn it off instantly by unchecking `Is_Enabled__c` in the org —
no deployment required.

```apex
if (FeatureFlag.isEnabled('bedrock.feature.externalSync')) {
  callExternalSystem();   // disable in seconds if the integration misbehaves
}
```

### Check the same flag repeatedly without query cost

Thanks to the per-transaction cache, checking a flag inside a loop is safe.
Only the first check queries; the rest are served from memory.

```apex
for (Account a : accounts) {
  if (FeatureFlag.isEnabled('bedrock.feature.enrichment')) {  // 1 query total
    enrich(a);
  }
}
```

> If you prefer, hoist the check out of the loop into a local `Boolean`. Both are
> fine — the cache makes them equivalent in query cost — but a local variable
> documents that the value does not change mid-loop.

### Blank names always return false

`isEnabled` treats a blank name as "off" before doing any work. This guards
against `null` flag names sneaking in from configuration or parameters.

```apex
Assert.areEqual(false, FeatureFlag.isEnabled(null),  'null name → false');
Assert.areEqual(false, FeatureFlag.isEnabled(''),    'empty name → false');
Assert.areEqual(false, FeatureFlag.isEnabled('   '), 'whitespace name → false');
```

## Setting Flags In Tests

Here is the problem `FeatureFlag.set` solves. Custom *metadata* records deployed
to an org are visible to test methods, but you usually **cannot rely on org
data** in a unit test — it makes tests environment-dependent, and you certainly
cannot insert new `Feature_Flag__mdt` records with DML the way you would a normal
SObject. So how do you test both the "flag on" and "flag off" branches of your
code deterministically?

`FeatureFlag.set(name, enabled)` is the answer. It writes a synthetic
`Feature_Flag__mdt` straight into the in-memory cache, so the very next
`isEnabled(name)` call returns whatever you set — no DML, no SOQL, no dependency
on what is deployed. This is the *Test Seam / in-memory override* pattern: the
production read path and the test override share the same cache, so the override
is transparent to the code under test.

### Turn a flag on for a test

Even if no `Feature_Flag__mdt` record exists for the name, `set(name, true)`
makes `isEnabled` return `true`.

```apex
// from FeatureFlagTest.testSet_overridesMissingFlag
FeatureFlag.set('bedrock.feature.missing', true);

Boolean enabled = FeatureFlag.isEnabled('bedrock.feature.missing');

Assert.areEqual(true, enabled, 'Expected set to enable a missing feature flag.');
```

### Turn a flag off for a test

Pass `false` to explicitly disable a flag — useful for asserting the legacy /
"flag off" branch of your code.

```apex
// from FeatureFlagTest.testSet_supportsFalseOverrides
FeatureFlag.set('bedrock.feature.false', false);

Boolean enabled = FeatureFlag.isEnabled('bedrock.feature.false');

Assert.areEqual(false, enabled, 'Expected set to explicitly disable a flag.');
```

### Test both branches of flag-guarded code

A typical service test seeds the flag, exercises the unit, then re-seeds and
exercises again — all in one method, all in memory.

```apex
@IsTest
static void appliesNewPricingOnlyWhenEnabled() {
  OrderProcessor processor = new OrderProcessor();
  Order__c order = new Order__c();

  // Flag ON → new path
  FeatureFlag.set('bedrock.feature.newPricing', true);
  processor.processOrder(order);
  Assert.areEqual('new', order.Pricing_Path__c, 'Expected the new pricing path when enabled.');

  // Flag OFF → legacy path
  FeatureFlag.set('bedrock.feature.newPricing', false);
  processor.processOrder(order);
  Assert.areEqual('legacy', order.Pricing_Path__c, 'Expected the legacy path when disabled.');
}
```

### Clearing an override with `set(name, null)`

Passing `null` as the value caches a record whose `Is_Enabled__c` is `null`.
Because `isEnabled` returns `flag != null && flag.Is_Enabled__c`, a `null`
`Is_Enabled__c` evaluates to `false` — so a `null` override effectively resets
the flag to the missing-flag default of "off".

```apex
// from FeatureFlagTest.testSet_nullClearsOverride
FeatureFlag.set('bedrock.feature.override', true);
FeatureFlag.set('bedrock.feature.override', null);   // back to default

Boolean enabled = FeatureFlag.isEnabled('bedrock.feature.override');

Assert.areEqual(false, enabled, 'Expected a null override to restore the default false.');
```

### Forcing a re-query with `clearCache()`

`clearCache()` is `@TestVisible`, so tests can call it to empty the cache —
discarding both overrides set via `set` and any cached SOQL results. The next
`isEnabled` for a name then performs a fresh lookup (which, for a name with no
deployed record, falls back to `false`).

```apex
// from FeatureFlagTest.testClearCache_removesCachedValues
FeatureFlag.set('bedrock.feature.cached', true);
Boolean overridden = FeatureFlag.isEnabled('bedrock.feature.cached');  // true (override)

FeatureFlag.clearCache();
Boolean restored = FeatureFlag.isEnabled('bedrock.feature.cached');    // false (re-queried, none found)

Assert.areEqual(true,  overridden, 'Override applied while cached.');
Assert.areEqual(false, restored,   'clearCache restores the default disabled state.');
```

## Gotchas & Testing Notes

- **No access modifier means private.** Only `isEnabled` and `set` are callable.
  `get` and `clearCache` are private; `clearCache` is reachable only from test
  code via `@TestVisible`. Don't build production logic against them.

- **Match on `Name__c`, not `DeveloperName`.** The query filters on the custom
  "Flag Key" field. The string you store in `Name__c` must equal the string you
  pass to `isEnabled` exactly — including case and the dotted namespace.

- **Fail closed is a feature, not a bug.** A typo'd name, a flag whose metadata
  was never deployed, or a blank name all return `false`. Guarded features stay
  off until a real, enabled record exists. Double-check the spelling if a flag
  "won't turn on."

- **The cache is per transaction.** Values are cached in static state, which
  lives for one Apex transaction. A change to a `Feature_Flag__mdt` record made
  mid-transaction (or the moment you deploy a new value) is not reflected until
  the next transaction. In tests, use `clearCache()` to force a re-read.

- **`set` only affects the current transaction's memory.** It does not insert
  metadata and does not persist anywhere. It is purely a test/override seam for
  the in-memory cache. Don't call it from production code expecting durable
  configuration.

- **`set(name, null)` reads as disabled.** A `null` `Is_Enabled__c` is falsy in
  the `flag != null && flag.Is_Enabled__c` check, so a `null` override behaves
  like "off," not "unknown."

- **Seed flags, don't rely on org data, in tests.** Use `FeatureFlag.set` to put
  the flag into a known state so your test is deterministic regardless of which
  `Feature_Flag__mdt` records happen to be deployed in the running org.

- **It is a boolean toggle only.** No percentages, no per-user/profile
  targeting, no non-boolean values. If you outgrow on/off, model the need with a
  custom setting or a richer custom metadata type rather than stretching
  `FeatureFlag`.
