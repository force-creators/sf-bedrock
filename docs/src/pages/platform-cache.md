---
layout: ../layouts/DocsLayout.astro
title: PlatformCache | sf-bedrock docs
description: Technical documentation and usage examples for the sf-bedrock PlatformCache Apex facade over Salesforce Platform Cache.
eyebrow: Foundation API
heading: PlatformCache
lede: A thin, mockable facade over Salesforce Platform Cache that gives you a uniform get / put / remove API across org and session partitions — and ships with a drop-in mock so cache-backed code is finally easy to unit test.
sections:
  - label: Purpose
    href: "#purpose"
  - label: How It Works
    href: "#how-it-works"
  - label: Public API
    href: "#public-api"
  - label: Examples
    href: "#examples"
  - label: Testing with PlatformCacheMock
    href: "#testing-with-platformcachemock"
  - label: Gotchas & Testing Notes
    href: "#gotchas-and-testing-notes"
---

## Purpose

`PlatformCache` is a **facade** over Salesforce
[Platform Cache](https://developer.salesforce.com/docs/atlas.en-us.apexref.meta/apexref/apex_namespace_cache.htm).
Platform Cache lets you store data in memory on the Salesforce side so that
expensive work — a slow callout, a heavy SOQL aggregation, a parsed
configuration blob — can be reused across transactions instead of recomputed
every time. Salesforce exposes two kinds of storage:

- **Org cache** (`Cache.Org`) — shared across all users and sessions in the org.
- **Session cache** (`Cache.Session`) — scoped to a single user's session.

The raw `Cache.Org` / `Cache.Session` namespaces are awkward to use directly:
the calls are static, scattered, and — most painfully — **almost impossible to
unit test**, because there is no supported way to fake what the platform cache
returns inside a test. `PlatformCache` wraps both namespaces behind one small
interface (`get`, `put`, `remove`) and a registry that can swap the real
partition for a mock. That single seam is what makes cache-backed code testable.

**Use `PlatformCache` when** you want to read or write Platform Cache from Apex
and you care about being able to unit test that code — which, in a Bedrock
codebase, is always.

**Reach for something else when** the data does not belong in a shared cache:
per-transaction memoization is better served by a plain `Map` static variable,
and durable data belongs in a record or Custom Metadata, not a cache that the
platform may evict at any time (see [Gotchas](#gotchas-and-testing-notes)).

## How It Works

Three ideas explain everything `PlatformCache` does.

### 1. It is a facade with a uniform interface

`PlatformCache` is an `abstract` class that declares three abstract methods —
`get`, `put`, and `remove`. Every concrete cache type implements that same
trio, so calling code never has to know whether it is talking to org cache,
session cache, or a mock:

```apex
new PlatformCache.Org('Bedrock').put('greeting', 'hello');
Object value = new PlatformCache.Org('Bedrock').get('greeting');
new PlatformCache.Org('Bedrock').remove('greeting');
```

`PlatformCache.Org` and `PlatformCache.Session` are the two concrete cache types
you instantiate. Both take a **partition name** (the API name of a Platform
Cache partition you have set up in your org) and differ only in which Salesforce
namespace they ultimately call.

### 2. A registry indirection makes it mockable

Notice that `Org` and `Session` do not call `Cache.Org` / `Cache.Session`
directly. Instead they delegate through a shared registry:

```apex
// Inside PlatformCache.Org
public override virtual Object get(String key) {
    return PlatformCache.partition.org(this.partitionName).get(key);
}
```

`PlatformCache.partition` is a static `PartitionRegistry`. When you ask it for a
partition by name and scope, it either returns a **registered mock** for that
partition or, if none is registered, hands back a real `PlatformCache.Partition`
that talks to the live `Cache.Org` / `Cache.Session` namespace. This is the
**dependency-injection seam**: in production the registry returns the real
partition; in a test you register a `PlatformCacheMock` and the same code
transparently reads and writes the mock instead.

Mocks are keyed by **both** partition name and scope (the registry builds a key
like `ORG:Bedrock` or `SESSION:Bedrock`), so an org-scoped mock and a
session-scoped mock for the same partition name never collide.

### 3. Scope is decided by the concrete type

The base `PlatformCache.Partition` carries a `scope` (defaulting to org scope)
and routes each call to the right Salesforce namespace:

```apex
public override virtual Object get(String key) {
    if (this.scope == PlatformCache.consts.SESSION_SCOPE)
        return Cache.Session.getPartition(this.partitionName).get(key);
    return Cache.Org.getPartition(this.partitionName).get(key);
}
```

`PlatformCache.Org` and `PlatformCache.Session` are thin subclasses that pick
the scope for you and route through the registry, so you choose org vs. session
simply by which class you `new` up.

## Public API

`PlatformCache` exposes two static properties, three abstract instance methods,
and a set of public inner classes you instantiate or subclass. The cache
implementation itself ships separately as `PlatformCacheMock`.

> **A note on access modifiers:** in Apex, a member declared with **no access
> modifier is private**. `PlatformCache` uses this deliberately. The mock-setter
> methods (`setMock`, `setOrgMock`, `setSessionMock`) and *every* method on
> `PartitionRegistry` (`org`, `session`, `key`, etc.) have no modifier, so they
> are **not public API** — the setters are reachable from tests only because
> they are marked `@TestVisible`. Likewise the `scope` field on `Partition` is
> private; only `partitionName` is public.

### Static members on `PlatformCache`

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| `partition` | `public static PartitionRegistry partition` | `PartitionRegistry` | The shared registry that resolves a partition name + scope to either a registered mock or a real partition. You rarely touch this directly. |
| `consts` | `public static final Constants consts` | `Constants` | Holder for the scope string constants `ORG_SCOPE` and `SESSION_SCOPE`. |

### Abstract instance methods (the cache interface)

Implemented by `Partition`, `Org`, `Session`, and `PlatformCacheMock`.

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| `get` | `get(String key)` | `Object` | Reads the value stored under `key`. Returns `null` on a cache miss. Cast the result to the type you stored. |
| `put` | `put(String key, Object value)` | `void` | Stores `value` under `key` in the partition. |
| `remove` | `remove(String key)` | `void` | Deletes the entry stored under `key`. |

### Public inner classes

| Class | Constructors | Description |
| --- | --- | --- |
| `PlatformCache.Org` | `Org(String partitionName)` | Org-scoped cache for the named partition. Routes through `Cache.Org`. The type you use most. |
| `PlatformCache.Session` | `Session(String partitionName)` | Session-scoped cache for the named partition. Routes through `Cache.Session`. |
| `PlatformCache.Partition` | `Partition(String partitionName)` / `Partition(String partitionName, String scope)` | The base partition. `Org`/`Session` extend it; the mock also extends it. Has one public field, `partitionName`. |
| `PlatformCache.Constants` | (instance is `PlatformCache.consts`) | Exposes the public final strings `ORG_SCOPE` (`'ORG'`) and `SESSION_SCOPE` (`'SESSION'`). |
| `PlatformCache.PartitionRegistry` | — | The DI registry behind `PlatformCache.partition`. Public class, but all of its methods are private — treat it as internal plumbing. |

> **There are no public *properties* you set directly to configure a cache.**
> Apart from the static `partition` and `consts` holders and the read-only
> `partitionName` field, a cache's behavior is determined entirely by which
> class you instantiate and the partition name you pass to its constructor.

### `PlatformCacheMock` (separate class)

`PlatformCacheMock extends PlatformCache.Partition` and is your test double. It
records every interaction and stores values in a plain in-memory `Map`.

| Member | Type | Description |
| --- | --- | --- |
| Constructor | `PlatformCacheMock(String partitionName)` | Creates a mock for the named partition. |
| `valuesByKey` | `public Map<String, Object>` | The backing store. Seed it to simulate cache hits; read it to assert what was written. |
| `gets` | `public List<String>` | Keys passed to `get`, in call order. |
| `puts` | `public List<String>` | Keys passed to `put`, in call order. |
| `removes` | `public List<String>` | Keys passed to `remove`, in call order. |

## Examples

### Write and read org cache

The everyday case. Construct a `PlatformCache.Org` for your partition and call
`put` / `get`. Because `get` returns `Object`, cast the result.

```apex
new PlatformCache.Org('Bedrock').put('greeting', 'hello');

String greeting = (String) new PlatformCache.Org('Bedrock').get('greeting');
```

### Handle a cache miss

`get` returns `null` when the key is absent (or was evicted). Always treat a
miss as the normal path — compute the value, then cache it.

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
new PlatformCache.Org('Bedrock').remove('greeting');
```

### Use session cache instead

Swap `Org` for `Session` to get per-user storage. The API is identical.

```apex
new PlatformCache.Session('Bedrock').put('greeting', 'hello');
String greeting = (String) new PlatformCache.Session('Bedrock').get('greeting');
```

### Wrap a partition in a typed subclass

A clean pattern (used by the tests) is to subclass `PlatformCache.Org` or
`PlatformCache.Session` so the partition name lives in one place and callers
never repeat the string literal:

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
Subclasses inherit the registry routing automatically, so they are mockable with
no extra wiring — see the subclass examples in the next section.

## Testing with PlatformCacheMock

Platform Cache is **notoriously hard to test directly.** There is no supported
API to pre-load `Cache.Org` with a value inside a test and have your code read
it back deterministically, and depending on partition setup the platform may
silently return `null`. The result is that naive cache code is either untestable
or flaky. `PlatformCache` solves this with the registry seam and a ready-made
double, `PlatformCacheMock`.

### The injection recipe

There are three setter entry points on `PlatformCache`, all `@TestVisible`:

- `PlatformCache.setMock(mock)` and `PlatformCache.setOrgMock(mock)` register a
  mock for the **org** scope (they are equivalent).
- `PlatformCache.setSessionMock(mock)` registers a mock for the **session** scope.

The mock is matched to your code by **partition name**, so construct it with the
same name your code under test uses. A tiny helper keeps tests tidy:

```apex
private static PlatformCacheMock cacheMock() {
    PlatformCacheMock cacheMock = new PlatformCacheMock('Bedrock');
    PlatformCache.setMock(cacheMock);   // org scope
    return cacheMock;
}

private static PlatformCacheMock sessionCacheMock() {
    PlatformCacheMock cacheMock = new PlatformCacheMock('Bedrock');
    PlatformCache.setSessionMock(cacheMock);   // session scope
    return cacheMock;
}
```

Once registered, any `new PlatformCache.Org('Bedrock')` in the code under test
transparently reads and writes the mock instead of the live cache.

### Assert what was written (put)

Seed nothing, exercise the code, then assert against the mock's `valuesByKey`
and its `puts` log. Note how the unused-channel lists (`gets`, `removes`) let
you prove the code did *only* what you expected.

```apex
@IsTest
static void testOrg_put() {
    PlatformCacheMock cacheMock = cacheMock();

    new PlatformCache.Org('Bedrock').put('greeting', 'hello');

    Assert.areEqual('hello', cacheMock.valuesByKey.get('greeting'),
        'Expected the put to store the value in the registered partition mock.');
    Assert.areEqual(new List<String>{ 'greeting' }, cacheMock.puts,
        'Expected the put to record the written key on the mock.');
    Assert.areEqual(0, cacheMock.gets.size(), 'Expected no reads.');
    Assert.areEqual(0, cacheMock.removes.size(), 'Expected no removes.');
}
```

### Simulate a cache hit (get)

To make the code under test "find" a value, pre-load the mock's `valuesByKey`
*before* exercising it. The mock records the key in `gets` and returns the
seeded value.

```apex
@IsTest
static void testOrg_get() {
    PlatformCacheMock cacheMock = cacheMock();
    cacheMock.valuesByKey.put('greeting', 'hello');   // seed the "hit"

    Object value = new PlatformCache.Org('Bedrock').get('greeting');

    Assert.areEqual('hello', value, 'Expected the seeded value back.');
    Assert.areEqual(new List<String>{ 'greeting' }, cacheMock.gets,
        'Expected the requested key to be recorded.');
}
```

To test the **cache-miss** branch instead, simply do not seed the key — `get`
returns `null`, exactly like the live cache on a miss.

### Assert a removal

```apex
@IsTest
static void testOrg_remove() {
    PlatformCacheMock cacheMock = cacheMock();
    cacheMock.valuesByKey.put('greeting', 'hello');

    new PlatformCache.Org('Bedrock').remove('greeting');

    Assert.areEqual(null, cacheMock.valuesByKey.get('greeting'),
        'Expected remove to delete the value from the mock.');
    Assert.areEqual(new List<String>{ 'greeting' }, cacheMock.removes,
        'Expected the removed key to be recorded.');
}
```

### Session scope works the same way

Use `setSessionMock` and `PlatformCache.Session`. Everything else is identical.

```apex
@IsTest
static void testSession_put() {
    PlatformCacheMock cacheMock = sessionCacheMock();

    new PlatformCache.Session('Bedrock').put('greeting', 'hello');

    Assert.areEqual('hello', cacheMock.valuesByKey.get('greeting'),
        'Expected the session put to store the value in the mock.');
    Assert.areEqual(new List<String>{ 'greeting' }, cacheMock.puts,
        'Expected the written key to be recorded.');
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

@IsTest
static void testSubclassOrg_get() {
    PlatformCacheMock cacheMock = cacheMock();          // mocks 'Bedrock', org scope
    cacheMock.valuesByKey.put('greeting', 'hello');

    Object value = new ExampleOrgCache().get('greeting');

    Assert.areEqual('hello', value,
        'Expected the subclass to read through the registered mock.');
}
```

### Org and session mocks are isolated

Register both and they stay separate — an org read hits the org mock, a session
read hits the session mock — because the registry keys on scope as well as name.

```apex
@IsTest
static void testOrgAndSessionMocksAreScopedSeparately() {
    PlatformCacheMock orgCacheMock = cacheMock();
    PlatformCacheMock sessionCacheMock = sessionCacheMock();
    orgCacheMock.valuesByKey.put('greeting', 'org hello');
    sessionCacheMock.valuesByKey.put('greeting', 'session hello');

    Object orgValue = new PlatformCache.Org('Bedrock').get('greeting');
    Object sessionValue = new PlatformCache.Session('Bedrock').get('greeting');

    Assert.areEqual('org hello', orgValue, 'Expected the org-scoped mock.');
    Assert.areEqual('session hello', sessionValue, 'Expected the session-scoped mock.');
}
```

## Gotchas & Testing Notes

- **A miss returns `null`, and misses are normal.** Platform Cache is not
  durable storage — the platform can evict any entry at any time under memory
  pressure or when its TTL expires. Always write code that recomputes on a
  `null` `get` rather than assuming a value is present.
- **Set up the partition first.** `PlatformCache.Org`/`Session` call
  `Cache.Org.getPartition(name)` / `Cache.Session.getPartition(name)`. The
  partition name you pass **must match a Platform Cache Partition you have
  configured** (with allocated capacity) in the org, or the live calls will not
  behave. In tests this does not matter, because the mock replaces the real
  partition entirely.
- **The mock is matched by partition name and scope.** If your code under test
  uses `new PlatformCache.Org('Bedrock')` but you register a mock named
  `'Other'`, no mock is found and the registry falls back to a real partition.
  Construct the `PlatformCacheMock` with the exact partition name your code
  uses, and use `setSessionMock` for session-scoped code.
- **`setMock` and `setOrgMock` are the same thing.** Both register an org-scoped
  mock; there is no separate "default" scope to worry about. Use
  `setSessionMock` for session scope.
- **Values are serialized by the platform.** Anything you `put` into real
  Platform Cache must be serializable, and large values count against your
  partition's capacity. The mock stores objects in a plain `Map` and does not
  enforce these limits, so a value that "works" in a mocked test could still be
  rejected or evicted in production — keep cached payloads small and simple.
- **`get` returns `Object`; cast it.** Store and retrieve the same type, and
  cast on the way out. A wrong cast surfaces as a runtime `TypeException`.
- **The registry is static and transaction-wide.** A mock you register stays
  registered for the rest of the transaction. Register it in your test setup (or
  a per-test helper like `cacheMock()` above) so each test starts from a known
  state.
- **Use the mock's interaction logs to assert intent, not just outcome.** The
  `gets`, `puts`, and `removes` lists let you prove the code touched the cache
  the expected number of times — for example, that a cache-hit path performed
  **zero** puts. Asserting the empty channels (`Assert.areEqual(0,
  mock.puts.size())`) catches accidental extra writes.
