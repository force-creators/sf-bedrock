---
layout: ../layouts/DocsLayout.astro
title: Generic | sf-bedrock docs
description: Technical documentation and usage examples for the sf-bedrock Generic Apex utility.
eyebrow: Tools
heading: Generic
lede: A dynamic, schema-less data container that reads and writes nested values by dotted/bracketed path, coerces them to the type you ask for, and converts cleanly to JSON or to a strongly-typed SObject — ideal for taming untyped JSON and integration payloads.
sections:
    - label: Overview
      href: "#overview"
    - label: Quickstart
      href: "#quickstart"
    - label: Examples
      href: "#examples"
    - label: Path Syntax
      href: "#path-syntax"
    - label: Type Coercion
      href: "#type-coercion"
    - label: Subclassing & transform()
      href: "#subclassing-and-transform"
    - label: How It Works
      href: "#how-it-works"
    - label: Public API
      href: "#public-api"
    - label: Notes & Edge Cases
      href: "#notes--edge-cases"
---

## Overview

`Generic` is a dynamic data container for working with **untyped, nested data**
— the kind you get back from `JSON.deserializeUntyped`, an external API, a
webhook body, or a loosely-structured `Map<String, Object>`. Instead of casting
your way through a tree of `Map<String, Object>` and `List<Object>` by hand, you
ask `Generic` for a value by **path**.

It wraps a single `Map<String, Object>` and gives you four things on top of it:

1. **Path access** — read (`get`) and write (`put`) deeply nested values with a
   `dot.and[bracket]` path string, without manual casting at each level.
2. **Type coercion** — ask `get` for a `Type` and it converts the raw value
   (often a `String` from JSON) into `Integer`, `Decimal`, `Boolean`, `Date`,
   `Datetime`, lists, or any deserializable type.
3. **Serialization** — turn the whole container back into a JSON string, or
   deserialize it directly into a concrete `SObject`.
4. **An extension point** — subclass it and override `mapping()` to define a
   reusable shape, then call `transform()` to materialize it.

**Use `Generic` when** you're consuming data whose structure is known at runtime
but awkward to model with classes — integration responses, configuration blobs,
dynamic field maps. It gives you safe, readable path access instead of nested
casts and `containsKey` checks.

**Reach for a typed Apex class (or `JSON.deserialize` into one) instead when**
the shape is stable and well-known. A real DTO gives you compile-time safety and
autocomplete. `Generic` trades those away for flexibility. Don't use it where a
plain `MyResponse` wrapper would do.

## Quickstart

Hydrate from a JSON string and read values by path. Bracket notation indexes
into lists; dot notation steps into maps.

```apex
Generic g = new Generic('{"user":{"name":"Alice","tags":["admin","beta"]}}');
String name = (String) g.get('user.name');      // 'Alice'
String tag  = (String) g.get('user.tags[0]');   // 'admin'
```

To build a container from scratch, use the default constructor and `put`. It
creates intermediate maps for you:

```apex
Generic g = new Generic();
g.put('user.profile.firstName', 'Bedrock');
String firstName = (String) g.get('user.profile.firstName'); // 'Bedrock'
```

## Examples

### Hydrate from JSON and read nested values

```apex
Generic g = new Generic('{"user":{"name":"Alice","tags":["admin","beta"]}}');

Assert.areEqual('Alice', g.get('user.name'), 'Reads a nested object value.');
Assert.areEqual('admin', g.get('user.tags[0]'), 'Reads a list value by index.');
```

### Build a container by path

The default constructor plus `put` lets you assemble nested data without
declaring any intermediate maps — `put` creates them for you.

```apex
Generic g = new Generic();
g.put('user.profile.firstName', 'Bedrock');

Assert.areEqual(
    'Bedrock',
    g.get('user.profile.firstName'),
    'Expected put to create the nested map and get to read it back.'
);
```

### Apply many paths at once

`put(Map<String, Object>)` is shorthand for several `put(path, value)` calls —
handy when you have a flat map of path → value pairs.

```apex
Generic g = new Generic();
g.put(new Map<String, Object>{
    'user.firstName' => 'Ada',
    'user.lastName'  => 'Lovelace'
});

Assert.areEqual('Ada', g.get('user.firstName'), 'First path applied.');
Assert.areEqual('Lovelace', g.get('user.lastName'), 'Second path applied.');
```

### Inline-build a complex object with path maps

For larger payloads, you can still stay inline by combining path keys with rich
values (`Map<String, Object>` and `List<Object>`). This gives you one readable
construction block without manually creating each intermediate node.

```apex
Generic payload = new Generic(new Map<String, Object>{
  'event.type' => 'invoice.generated',
  'event.meta.source' => 'billing-engine',
  'event.meta.retryCount' => 0,
  'event.account.id' => '001000000000001AAA',
  'event.account.name' => 'Acme',
  'event.lines' => new List<Object>{
    new Map<String, Object>{
      'sku' => 'A-100',
      'quantity' => 2,
      'amount' => 49.99
    },
    new Map<String, Object>{
      'sku' => 'B-200',
      'quantity' => 1,
      'amount' => 99.00
    }
  }
});

Assert.areEqual('invoice.generated', payload.get('event.type'),
  'Expected path map puts to build the top-level event values.');
Assert.areEqual('Acme', payload.get('event.account.name'),
  'Expected nested account paths to be created inline.');
Assert.areEqual('B-200', payload.get('event.lines[1].sku'),
  'Expected list/map values supplied inline to remain path-addressable.');
```

### Safe access to missing data

You don't need `containsKey` guards — a missing key or an out-of-bounds index
simply yields `null`.

```apex
Generic g = new Generic('{"user":{"tags":["admin"]}}');

Assert.areEqual(null, g.get('user.missing'), 'Missing map key returns null.');
Assert.areEqual(null, g.get('user.tags[2]'), 'Out-of-bounds index returns null.');
```

### Convert to JSON or to an SObject

`json()` serializes the backing map; `sObject(Type)` deserializes it into a
concrete record. If your keys match field API names, you get a populated SObject.

```apex
Generic g = new Generic();
g.put('Name', 'Acme');

String json = g.json();                                   // {"Name":"Acme"}
Account account = (Account) g.sObject(Account.class);

Assert.isTrue(json.contains('"Name":"Acme"'), 'json() serializes the map.');
Assert.areEqual('Acme', account.Name, 'sObject() builds a typed Account.');
```

### Realistic example: normalizing an integration payload

A service receives a webhook body and needs to validate and read specific
fields. `Generic` handles the path access; the service stays readable.

```apex
public inherited sharing class WebhookService {
    public void handle(String body) {
        Generic payload = new Generic(body);

        String eventType = (String) payload.get('event.type');
        String accountId = (String) payload.get('event.data.account_id');
        Integer retryCount = (Integer) payload.get('meta.retry', Integer.class);

        if (eventType == null || accountId == null) {
            return; // nothing to process
        }

        // downstream work uses typed values, not raw Objects
        process(eventType, accountId, retryCount != null ? retryCount : 0);
    }

    void process(String eventType, String accountId, Integer retryCount) {
        /* ... */
    }
}
```

To test this in isolation, construct a `Generic` directly from a `Map` and pass
its `json()` output as the payload — no real HTTP call required:

```apex
@istest static void testHandle_validPayload() {
    Generic payload = new Generic();
    payload.put('event.type', 'account.updated');
    payload.put('event.data.account_id', '001000000000001AAA');
    payload.put('meta.retry', 0);

    // Exercise the service with the serialized payload
    new WebhookService().handle(payload.json());

    // Assert downstream side-effects here
}
```

## Path Syntax

A path is a `String` that names a location in the nested structure. Before
walking, `Generic` normalizes it: `[` becomes `.`, `]` is removed, and the
result is split on `.`. So all of these describe the same traversal:

| Path            | Normalized segments  | Walks                        |
| --------------- | -------------------- | ---------------------------- |
| `user.name`     | `user`, `name`       | map → map key                |
| `user.tags[0]`  | `user`, `tags`, `0`  | map → map → list index 0     |
| `items[1].name` | `items`, `1`, `name` | map → list index 1 → map key |

Rules to keep in mind:

- **Map segments are keys; list segments are indices.** A numeric segment is
  only treated as an index when the current node is actually a `List<Object>`.
- **Missing keys and out-of-range indices return `null`** from `get` — the walk
  stops safely rather than throwing.
- **`put` only descends through maps.** It creates intermediate `Map<String,
Object>` nodes as it goes; it does **not** create or grow lists. Writing into
  an existing list element by index is not supported by `put`.

## Type Coercion

`get(String path, Type target)` returns the value converted to `target`. This is
the feature that makes integration data usable: JSON numbers and dates often
arrive as `String`s, and coercion turns them into real Apex types.

```apex
Generic g = new Generic(new Map<String, Object>{
    'count'   => '42',
    'enabled' => 'true',
    'amount'  => '10.50'
});

Integer count   = (Integer) g.get('count', Integer.class);   // 42
Boolean enabled = (Boolean) g.get('enabled', Boolean.class); // true
Decimal amount  = (Decimal) g.get('amount', Decimal.class);  // 10.50
```

Dates and datetimes coerce from ISO-style strings:

```apex
Generic g = new Generic(new Map<String, Object>{
    'startDate' => '2026-01-15',
    'runAt'     => '2026-01-15 10:30:00'
});

Date start    = (Date) g.get('startDate', Date.class);       // 2026-01-15
Datetime when = (Datetime) g.get('runAt', Datetime.class);   // 2026-01-15 10:30:00
```

Collection targets are supported too. Asking for `List<Map<String,
Object>>.class` rebuilds a list of maps from a raw `List<Object>`:

```apex
Generic g = new Generic('{"items":[{"name":"A"},{"name":"B"}]}');

List<Map<String, Object>> items =
    (List<Map<String, Object>>) g.get('items', List<Map<String, Object>>.class);

Assert.areEqual(2, items.size(), 'Coerced into a list of maps.');
Assert.areEqual('B', items[1].get('name'), 'Each item is a usable map.');
```

### Supported targets

| `target`                          | Conversion                                                          |
| --------------------------------- | ------------------------------------------------------------------- |
| `null` or `Object.class`          | Returns the raw value unchanged.                                    |
| `String.class`                    | `String.valueOf(value)`                                             |
| `Integer.class`                   | `Integer.valueOf(String.valueOf(value))`                            |
| `Decimal.class`                   | `Decimal.valueOf(String.valueOf(value))`                            |
| `Boolean.class`                   | `Boolean.valueOf(String.valueOf(value))`                            |
| `Date.class`                      | `Date.valueOf(String.valueOf(value))`                               |
| `Datetime.class`                  | `Datetime.valueOf(String.valueOf(value))`                           |
| `List<Object>.class`              | Direct cast to `List<Object>`.                                      |
| `Map<String, Object>.class`       | Direct cast to `Map<String, Object>`.                               |
| `List<Map<String, Object>>.class` | Rebuilds each element as a `Map<String, Object>`.                   |
| Any other `Type`                  | JSON round-trip: `JSON.deserialize(JSON.serialize(value), target)`. |

> **A `null` value short-circuits.** If the value at the path is `null`,
> coercion returns `null` regardless of `target` — it never tries to convert
> `null`. Combined with the safe-path behavior, `get('missing.path', Integer.class)`
> returns `null`, not an exception.

## Subclassing & transform()

`Generic` is declared `virtual`, and `mapping()` / `transform()` are `virtual`
hooks — this is the **Template Method** pattern. The base `mapping()` returns an
empty map. `transform()` feeds `mapping()` into a new `Generic` and hands back
its backing map. On the base class, both return empty:

```apex
Generic g = new Generic();
Assert.areEqual(0, g.mapping().size(), 'Base mapping() is empty.');
Assert.areEqual(0, g.transform().size(), 'Base transform() is empty.');
```

Subclass `Generic` and **override `mapping()`** to declare a reusable shape.
`transform()` materializes it for you. This is useful for building a canonical
output structure — for example, normalizing an inbound payload into the map your
downstream code expects:

```apex
public class StatusReport extends Generic {
    public String status;
    public Integer version;
    public String source;

    public StatusReport(String genericString) {
        // Example inbound payload:
        // {"payload":{"state":"ready","rev":"1"},"meta":{"source":"sync"}}
        super(genericString);
        this.status = (String) this.get('payload.state');
        this.version = (Integer) this.get('payload.rev', Integer.class);
        this.source = (String) this.get('meta.source');
    }

    // Calling transform().json() on a StatusReport hydrated from the example payload returns:
    // {"report.status":"ready","report.version":1,"report.audit.source":"sync"}
    public override Map<String, Object> mapping() {
        return new Map<String, Object>{
            'report.status' => this.status,
            'report.version' => this.version,
            // Nested audit field in the outbound structure.
            'report.audit.source' => this.source
        };
    }
}
```

A typical subclass uses the constructor to hydrate DTO-style properties from
incoming JSON, then uses `mapping()` to build the outgoing shape. This keeps
input parsing and output shaping explicit and testable.

## How It Works

Three ideas explain everything `Generic` does.

### 1. It wraps one `Map<String, Object>`

Internally `Generic` holds a single `Map<String, Object>` (the `generic` field,
which is `protected`, not public). Every constructor's job is to populate that
map:

- `new Generic()` starts empty.
- `new Generic(String json)` runs `JSON.deserializeUntyped` and casts the result
  to `Map<String, Object>`.
- `new Generic(Map<String, Object> source)` **copies** the entries of `source`
  into a fresh map (a defensive copy — see [Notes & Edge Cases](#notes--edge-cases)).

Everything else operates on that one map.

### 2. Paths are walked recursively

A path like `user.tags[0]` is first **normalized** into a list of segments —
`['user', 'tags', '0']` — then the container walks the tree one segment at a
time. At each step it inspects the current node:

- If the node is a `Map<String, Object>`, the segment is used as a **key**.
- If the node is a `List<Object>`, the segment is parsed as an **integer index**.

`get` returns `null` when a map segment is missing or a list index is past the
end of the list. List segments must still be valid non-negative integers; a path
like `tags[abc]` is not a safe list access. `put` is the mirror image for maps:
as it walks toward the last segment, it **creates the intermediate maps it
needs**, so `put('a.b.c', x)` works even on an empty container.

### 3. Coercion and conversion go through JSON

When you ask `get` for a `Type`, simple targets (`Integer`, `Boolean`, `Date`,
etc.) are converted with the matching `valueOf` call. Anything more complex gets
a **JSON round-trip**: serialize the raw value, then `JSON.deserialize` it into
the requested type. The same trick powers `sObject()`, which serializes the
whole container and deserializes it into the `SObject` type you pass. That's why
a string value of `'42'` from JSON can come back as a real `Integer`, and why
the map can become an `Account`.

## Public API

`Generic` is declared `public virtual with sharing`. It exposes three
constructors, path `get`/`put` methods, conversion helpers, and two `virtual`
extension methods.

> **A note on "properties":** `Generic` has **no public properties**. Its only
> instance state is the `generic` field, which is **`protected`** — visible to
> subclasses but not to outside callers. To read the underlying map from outside
> the class, use the `generic()` method. All normal state changes go through
> `put`.

> **A note on access modifiers:** in Apex, a member with **no** access modifier
> is **private**. Generic has private helpers for type conversion and path
> normalization. They are not part of the public surface; use the string path
> methods below.

| Member      | Signature                                                              | Returns               | Description                                                                                                                            |
| ----------- | ---------------------------------------------------------------------- | --------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Constructor | `Generic()`                                                            | `Generic`             | Creates an empty container backed by a new `Map<String, Object>`.                                                                      |
| Constructor | `Generic(String unknown)`                                              | `Generic`             | Hydrates the container from a JSON string via `JSON.deserializeUntyped`. The JSON's top level must be an object.                       |
| Constructor | `Generic(Map<String, Object> unknown)`                                 | `Generic`             | Copies the entries of an existing map into a new backing map (defensive copy).                                                         |
| `get`       | `get(String path)`                                                     | `Object`              | Returns the raw value at `path`, or `null` if a map segment is missing or a positive list index is out of bounds.                      |
| `get`       | `get(String path, Type target)`                                        | `Object`              | Returns the value at `path` coerced to `target`. If `target` is `null`, behaves like `get(path)`. See [Type Coercion](#type-coercion). |
| `get`       | `get(Object current, List<String> parts, Integer index)`               | `Object`              | Recursive walker used internally by the two `get` overloads. Public, but you normally call the string overloads.                       |
| `put`       | `put(String key, Object value)`                                        | `void`                | Writes `value` at the dotted/bracketed path `key`, creating intermediate maps as needed.                                               |
| `put`       | `put(Map<String, Object> paths)`                                       | `void`                | Convenience: applies every entry of the map as a `put(path, value)` call.                                                              |
| `put`       | `put(Object current, List<String> parts, Integer index, Object value)` | `void`                | Recursive writer used internally by the other `put` overloads.                                                                         |
| `json`      | `json()`                                                               | `String`              | Serializes the backing map to a JSON string via `JSON.serialize`.                                                                      |
| `sObject`   | `sObject(Type target)`                                                 | `SObject`             | Serializes the container and deserializes it into the given `SObject` type.                                                            |
| `generic`   | `generic()`                                                            | `Map<String, Object>` | Returns the backing map directly (live reference, not a copy).                                                                         |
| `mapping`   | `mapping()` (`virtual`)                                                | `Map<String, Object>` | Extension hook. Returns an empty map by default; override in a subclass to declare a shape.                                            |
| `transform` | `transform()` (`virtual`)                                              | `Map<String, Object>` | Builds a new `Generic` from `mapping()` and returns its backing map. See [Subclassing & transform()](#subclassing-and-transform).      |

> **About the recursive overloads.** `get(Object, List<String>, Integer)` and
> `put(Object, List<String>, Integer, Object)` are public in the current class,
> but they expect already-normalized path segments. In day-to-day code, call
> `get(path)`, `get(path, type)`, and `put(key, value)`.

## Notes & Edge Cases

- **The string JSON constructor expects a top-level object.** `new Generic(json)`
  casts the deserialized result to `Map<String, Object>`. If the JSON root is an
  array or a scalar, you'll get a cast exception. Wrap it in an object first.
- **`get` is safe for missing map keys and out-of-range positive list indexes;
  malformed list indexes can still throw.** A path like `items[99]` returns
  `null` when the list is shorter. A path like `items[abc]` can throw because the
  list segment cannot be parsed as an integer.
- **Coercion can throw.** Converting an incompatible value still fails. For
  example, `get('name', Integer.class)` on a non-numeric string raises a
  `TypeException`. Coerce only values you expect to fit the target type.
- **`put` builds maps, not lists.** Writing `a.b.c` creates intermediate maps,
  but `put` cannot create list elements or set an item by index. To write into a
  list, build the list yourself and `put` it as a whole value.
- **`generic()` returns a live reference.** It hands back the actual backing map,
  not a copy — mutating the returned map mutates the container. The `Map`
  _constructor_, by contrast, copies its input, so later changes to the source
  map do **not** leak in:
    ```apex
    Map<String, Object> source = new Map<String, Object>{ 'status' => 'initial' };
    Generic g = new Generic(source);
    source.put('status', 'changed');           // mutates source only
    Assert.areEqual('initial', g.get('status'), 'Constructor took a defensive copy.');
    ```
- **`sObject()` is only as valid as your keys.** Deserialization into an SObject
  succeeds only when keys map to real field API names of the correct types.
  Mismatches throw during deserialization. It's a great way to fabricate records
  for tests — but, like any deserialized SObject, those records carry whatever
  values you put in, including normally read-only ones. Keep them on the mocking
  side of your tests, not for DML.
- **Numeric path segments are indices only inside lists.** `tags[0]` walks a
  list, but if `tags` happens to be a map, `0` is treated as the literal key
  `'0'`. The segment's meaning depends on the node type at that point in the walk.
- **Coercion reads, it does not store.** `get(path, type)` returns a converted
  copy. It does not change what's stored in the container. The backing map keeps
  the original raw value.
- **Don't reach for the recursive overloads.** `get(Object, List<String>,
Integer)` and the four-argument `put` exist for internal recursion. Use the
  string-path overloads. The recursive ones expect already-normalized segment
  lists and a starting index.
- **There is no mock for `Generic`.** `Generic` is a pure in-memory value
  container with no I/O. Test it directly: construct with a known payload and
  assert what `get` returns. No seams to replace, no setup beyond the constructor.
