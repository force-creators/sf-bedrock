---
layout: ../layouts/DocsLayout.astro
title: PlatformCache | sf-bedrock docs
description: Read and write Salesforce Platform Cache through a small API that can be tested with an in-memory mock.
eyebrow: Tools
heading: PlatformCache
lede: PlatformCache gives org and session cache the same get, put, and remove API, plus an in-memory mock for cache-backed unit tests.
sections:
    - label: Overview
      href: "#overview"
    - label: Quickstart
      href: "#quickstart"
    - label: Examples
      href: "#examples"
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

`PlatformCache` wraps Salesforce
[Platform Cache](https://developer.salesforce.com/docs/atlas.en-us.apexref.meta/apexref/apex_namespace_namespaces_cache.htm).
Platform Cache lets you store data in memory on the Salesforce side so that
expensive work — a slow callout, a heavy SOQL aggregation, a parsed
configuration blob — can be reused across transactions instead of recomputed
every time. Salesforce exposes two kinds of storage:

- **Org cache** (`Cache.Org`) — shared across all users and sessions in the org.
- **Session cache** (`Cache.Session`) — scoped to a single user's session.

The raw `Cache.Org` / `Cache.Session` namespaces are awkward to use directly.
The calls are static, scattered, and hard to test. There is no supported way to
fake what the platform cache returns inside a test. `PlatformCache` gives both
scopes the same three calls (`get`, `put`, `remove`) and lets tests register an
in-memory mock for the partition your code uses.

**Use `PlatformCache` when** you want to read or write Platform Cache from Apex
and you care about being able to unit test that code — which, in a Bedrock
codebase, is always.

**Reach for something else when** the data does not belong in a shared cache:
per-transaction memoization is better served by a plain `Map` static variable,
and durable data belongs in a record or Custom Metadata, not a cache that the
platform may evict at any time.

## Quickstart

Construct a `PlatformCache.Org` with your partition name, write a value with
`put`, and read it back with `get`. Cast the result — `get` returns `Object`.

```apex
new PlatformCache.Org('Bedrock').put('configKey', configValue);

String configKey = (String) new PlatformCache.Org('Bedrock').get('configKey');
```

Swap `Org` for `Session` to get per-user storage. The API is identical.

## Examples

### Handle a cache miss

`get` returns `null` on a miss. Always treat the miss as the normal path —
compute the value, then cache it.

```apex
PlatformCache.Org cache = new PlatformCache.Org('Bedrock');

String config = (String) cache.get('config');
if (config == null) {
    config = loadConfigTheExpensiveWay();  // SOQL, callout, etc.
    cache.put('config', config);
}
return config;
```

### Remove an entry

```apex
new PlatformCache.Org('Bedrock').remove('config');
```

### Use session cache

Session cache is scoped to a single user's session. The API is identical to
org cache.

```apex
new PlatformCache.Session('Bedrock').put('greeting', 'hello');
String greeting = (String) new PlatformCache.Session('Bedrock').get('greeting');
```

### Wrap a partition in a typed subclass

A clean pattern is to subclass `PlatformCache.Org` or `PlatformCache.Session`
so the partition name lives in one place and callers never repeat the string
literal. Subclasses stay mockable with no extra wiring.

```apex
public inherited sharing class BedrockCache extends PlatformCache.Org {
    public BedrockCache() {
        super('Bedrock');
    }
}

// Callers no longer hard-code the partition name:
new BedrockCache().put('greeting', 'hello');
String greeting = (String) new BedrockCache().get('greeting');
```

The mirror image works for session scope by extending `PlatformCache.Session`.

## Testing

Platform Cache is **notoriously hard to test directly.** There is no supported
API to pre-load `Cache.Org` with a value inside a test and have your code read
it back deterministically. Depending on partition setup, the platform may
silently return `null`. Naive cache code is either untestable or flaky.

`PlatformCache` solves this by letting tests register a `PlatformCacheMock`
under a partition name and scope. From that point, any code that constructs
`new PlatformCache.Org('Bedrock')` transparently reads and writes the mock
instead of the live cache.

### The injection recipe

Three `@TestVisible` setters on `PlatformCache` handle registration:

- `PlatformCache.setMock(mock)` and `PlatformCache.setOrgMock(mock)` register
  a mock for the **org** scope (they are equivalent).
- `PlatformCache.setSessionMock(mock)` registers a mock for the **session** scope.

The mock is matched to your code by **partition name and scope**, so construct
it with the exact name your code under test uses. A small helper keeps tests
tidy:

```apex
private static PlatformCacheMock cacheMock() {
    PlatformCacheMock mock = new PlatformCacheMock('Bedrock');
    PlatformCache.setMock(mock);   // org scope
    return mock;
}

private static PlatformCacheMock sessionCacheMock() {
    PlatformCacheMock mock = new PlatformCacheMock('Bedrock');
    PlatformCache.setSessionMock(mock);   // session scope
    return mock;
}
```

### Assert what was written (put)

Seed nothing, exercise the code, then assert against the mock's `valuesByKey`
and its `puts` log. Asserting the unused-channel lists proves the code did only
what you expected.

```apex
@istest
static void testOrg_put() {
    PlatformCacheMock mock = cacheMock();

    new PlatformCache.Org('Bedrock').put('greeting', 'hello');

    Assert.areEqual('hello', mock.valuesByKey.get('greeting'),
        'Expected the put to store the value in the registered partition mock.');
    Assert.areEqual(new List<String>{ 'greeting' }, mock.puts,
        'Expected the put to record the written key on the mock.');
    Assert.areEqual(0, mock.gets.size(), 'Expected no reads.');
    Assert.areEqual(0, mock.removes.size(), 'Expected no removes.');
}
```

### Simulate a cache hit (get)

To make the code under test "find" a value, pre-load the mock's `valuesByKey`
before exercising it. The mock records the key in `gets` and returns the seeded
value. To test the cache-miss branch instead, simply do not seed the key —
`get` returns `null`, exactly like the live cache on a miss.

```apex
@istest
static void testOrg_get() {
    PlatformCacheMock mock = cacheMock();
    mock.valuesByKey.put('greeting', 'hello');   // seed the "hit"

    Object value = new PlatformCache.Org('Bedrock').get('greeting');

    Assert.areEqual('hello', value, 'Expected the seeded value back.');
    Assert.areEqual(new List<String>{ 'greeting' }, mock.gets,
        'Expected the requested key to be recorded.');
}
```

### Assert a removal

```apex
@istest
static void testOrg_remove() {
    PlatformCacheMock mock = cacheMock();
    mock.valuesByKey.put('greeting', 'hello');

    new PlatformCache.Org('Bedrock').remove('greeting');

    Assert.areEqual(null, mock.valuesByKey.get('greeting'),
        'Expected remove to delete the value from the mock.');
    Assert.areEqual(new List<String>{ 'greeting' }, mock.removes,
        'Expected the removed key to be recorded.');
}
```

### Org and session mocks are isolated

Register both scopes and they stay separate — an org read hits the org mock, a
session read hits the session mock — because the registry keys on scope as well
as name.

```apex
@istest
static void testOrgAndSessionMocksAreScopedSeparately() {
    PlatformCacheMock orgMock = cacheMock();
    PlatformCacheMock sessionMock = sessionCacheMock();
    orgMock.valuesByKey.put('greeting', 'org hello');
    sessionMock.valuesByKey.put('greeting', 'session hello');

    Object orgValue = new PlatformCache.Org('Bedrock').get('greeting');
    Object sessionValue = new PlatformCache.Session('Bedrock').get('greeting');

    Assert.areEqual('org hello', orgValue, 'Expected the org-scoped mock.');
    Assert.areEqual('session hello', sessionValue, 'Expected the session-scoped mock.');
}
```

### Subclasses are mockable for free

Because the typed subclass pattern routes through the same registry, registering
a mock for its partition name is all you need — you do not mock the subclass
itself.

```apex
private inherited sharing class ExampleOrgCache extends PlatformCache.Org {
    public ExampleOrgCache() {
        super('Bedrock');
    }
}

@istest
static void testSubclassOrg_get() {
    PlatformCacheMock mock = cacheMock();          // mocks 'Bedrock', org scope
    mock.valuesByKey.put('greeting', 'hello');

    Object value = new ExampleOrgCache().get('greeting');

    Assert.areEqual('hello', value,
        'Expected the subclass to read through the registered mock.');
}
```

## How It Works

Three ideas explain everything `PlatformCache` does.

### 1. It is a facade with a uniform interface

`PlatformCache` is an `abstract` class that declares three abstract methods —
`get`, `put`, and `remove`. Every concrete cache type implements that same trio,
so calling code never has to know whether it is talking to org cache, session
cache, or a mock.

`PlatformCache.Org` and `PlatformCache.Session` are the two concrete types you
instantiate. Both take a **partition name** (the API name of a Platform Cache
partition configured in your org) and differ only in which Salesforce namespace
they ultimately call.

### 2. Registered mocks make it testable

`Org` and `Session` do not call `Cache.Org` / `Cache.Session` directly. Instead
they delegate through a shared registry:

```apex
// Inside PlatformCache.Org
public override virtual Object get(String key) {
    return PlatformCache.partition.org(this.partitionName).get(key);
}
```

When code asks for a partition by name and scope, Bedrock uses a registered mock
when one exists. If no mock is registered, it uses the live Platform Cache
partition. Mocks are keyed by **both** partition name and scope, so an org-scoped
mock and a session-scoped mock for the same partition name never collide.

### 3. Scope is decided by the concrete type

`PlatformCache.Org` and `PlatformCache.Session` are thin `virtual` subclasses
of `PlatformCache.Partition` that pick the scope for you. `Partition` itself
routes each call to the right Salesforce namespace:

```apex
public override virtual Object get(String key) {
    if (this.scope == PlatformCache.consts.SESSION_SCOPE)
        return Cache.Session.getPartition(this.partitionName).get(key);
    return Cache.Org.getPartition(this.partitionName).get(key);
}
```

You choose org vs. session simply by which class you `new` up.

## Public API

`PlatformCache` is declared `public abstract inherited sharing`. It exposes two
static members, three abstract instance methods, and a set of public inner
classes you instantiate or subclass. The test double ships separately as
`PlatformCacheMock`.

> **A note on access modifiers:** in Apex, a member declared with **no access
> modifier is private**. `PlatformCache` uses this deliberately. The mock-setter
> methods (`setMock`, `setOrgMock`, `setSessionMock`) have no modifier, so they
> are **not public API** — they are reachable from tests only because they are
> marked `@TestVisible`. Likewise every method on `PartitionRegistry` (`org`,
> `session`, `key`, etc.) is private and not a caller-facing API. The
> `scope` field on `Partition` is also private; only `partitionName` is public.
> Some framework helpers are technically visible because Bedrock is source-first;
> treat this table as the supported cache surface for app teams.

### Static members on `PlatformCache`

| Member      | Signature                                   | Returns             | Description                                                                                                        |
| ----------- | ------------------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `partition` | `public static PartitionRegistry partition` | `PartitionRegistry` | Shared resolver for registered mocks and real partitions. Application code should not need to touch this directly. |
| `consts`    | `public static final Constants consts`      | `Constants`         | Holder for the scope string constants `ORG_SCOPE` and `SESSION_SCOPE`.                                             |

### Abstract instance methods (the cache interface)

Implemented by `Partition`, `Org`, `Session`, and `PlatformCacheMock`.

| Member   | Signature                       | Returns  | Description                                                                                                 |
| -------- | ------------------------------- | -------- | ----------------------------------------------------------------------------------------------------------- |
| `get`    | `get(String key)`               | `Object` | Reads the value stored under `key`. Returns `null` on a cache miss. Cast the result to the type you stored. |
| `put`    | `put(String key, Object value)` | `void`   | Stores `value` under `key` in the partition.                                                                |
| `remove` | `remove(String key)`            | `void`   | Deletes the entry stored under `key`.                                                                       |

### Public inner classes

| Class                             | Constructors                                                                        | Description                                                                                                                                                     |
| --------------------------------- | ----------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PlatformCache.Org`               | `Org(String partitionName)`                                                         | Org-scoped cache for the named partition. Routes through `Cache.Org` via the registry. The type you use most. `virtual` — extend it to create a typed subclass. |
| `PlatformCache.Session`           | `Session(String partitionName)`                                                     | Session-scoped cache for the named partition. Routes through `Cache.Session` via the registry. `virtual` — extend it for typed session-cache subclasses.        |
| `PlatformCache.Partition`         | `Partition(String partitionName)` / `Partition(String partitionName, String scope)` | The base partition. `Org` and `Session` extend it; `PlatformCacheMock` also extends it. Has one public field, `partitionName`. Defaults to org scope.           |
| `PlatformCache.Constants`         | (instance is `PlatformCache.consts`)                                                | Exposes the public final strings `ORG_SCOPE` (`'ORG'`) and `SESSION_SCOPE` (`'SESSION'`).                                                                       |
| `PlatformCache.PartitionRegistry` | —                                                                                   | Resolver behind `PlatformCache.partition`. Public class, but its methods are private; application code should use `Org`, `Session`, or a typed subclass.        |

> **There are no public properties you set directly to configure a cache.**
> Apart from the static `partition` and `consts` holders and the `partitionName`
> field on `Partition`, a cache's behavior is determined entirely by which class
> you instantiate and the partition name you pass to its constructor.

### `PlatformCacheMock` (separate class)

`PlatformCacheMock extends PlatformCache.Partition` and is your test double. It
records every interaction and stores values in a plain in-memory `Map`.

| Member        | Type                                      | Description                                                                            |
| ------------- | ----------------------------------------- | -------------------------------------------------------------------------------------- |
| Constructor   | `PlatformCacheMock(String partitionName)` | Creates a mock for the named partition.                                                |
| `valuesByKey` | `public Map<String, Object>`              | The backing store. Seed it to simulate cache hits; read it to assert what was written. |
| `gets`        | `public List<String>`                     | Keys passed to `get`, in call order.                                                   |
| `puts`        | `public List<String>`                     | Keys passed to `put`, in call order.                                                   |
| `removes`     | `public List<String>`                     | Keys passed to `remove`, in call order.                                                |

## Notes & Edge Cases

- **A miss returns `null`, and misses are normal.** Platform Cache is not
  durable storage — the platform can evict any entry at any time under memory
  pressure or when its TTL expires. Always write code that recomputes on a
  `null` return from `get` rather than assuming a value is present.
- **Set up the partition first.** `PlatformCache.Org` / `Session` call
  `Cache.Org.getPartition(name)` / `Cache.Session.getPartition(name)`. The
  partition name you pass must match a Platform Cache partition configured
  (with allocated capacity) in the org, or the live calls will not behave.
  In tests this does not matter — the mock replaces the real partition entirely.
- **The mock is matched by partition name and scope.** If your code uses
  `new PlatformCache.Org('Bedrock')` but you register a mock named `'Other'`,
  no mock is found and the registry falls back to a real partition. Construct
  the `PlatformCacheMock` with the exact partition name your code uses, and use
  `setSessionMock` for session-scoped code.
- **`setMock` and `setOrgMock` are the same thing.** Both register an org-scoped
  mock; there is no separate "default" scope to worry about. Use `setSessionMock`
  for session scope.
- **Values are serialized by the platform.** Anything you `put` into real
  Platform Cache must be serializable. Large values also count against your
  partition's capacity. The mock stores objects in a plain `Map` and does not
  enforce these limits, so a value that works in a mocked test could still be
  rejected or evicted in production. Keep cached payloads small and simple.
- **`get` returns `Object`; cast it.** Store and retrieve the same type, and
  cast on the way out. A wrong cast surfaces as a runtime `TypeException`.
- **The registry is static and transaction-wide.** A mock you register stays
  registered for the rest of the transaction. Register it in a per-test helper
  so each test starts from a known state.
- **Use the mock's interaction logs to assert intent, not just outcome.** The
  `gets`, `puts`, and `removes` lists let you prove the code touched the cache
  the expected number of times. For example, you can confirm that a cache-hit
  path performed zero puts. Asserting the empty channels
  (`Assert.areEqual(0, mock.puts.size(), 'Expected no writes.')`) catches
  accidental extra writes.
