---
layout: ../layouts/DocsLayout.astro
title: Generic | sf-bedrock docs
description: Technical documentation and usage examples for the sf-bedrock Generic Apex utility.
eyebrow: Foundation API
heading: Generic
lede: A dynamic, schema-less data container that reads and writes nested values by dotted/bracketed path, coerces them to the type you ask for, and converts cleanly to JSON or to a strongly-typed SObject — ideal for taming untyped JSON and integration payloads.
sections:
  - label: Purpose
    href: "#purpose"
  - label: How It Works
    href: "#how-it-works"
  - label: Public API
    href: "#public-api"
  - label: Path Syntax
    href: "#path-syntax"
  - label: Examples
    href: "#examples"
  - label: Type Coercion
    href: "#type-coercion"
  - label: Subclassing & transform()
    href: "#subclassing-and-transform"
  - label: Gotchas & Testing Notes
    href: "#gotchas-and-testing-notes"
---

## Purpose

`Generic` is a dynamic data container for working with **untyped, nested data**
— the kind you get back from `JSON.deserializeUntyped`, an external API, a
webhook body, or a loosely-structured `Map<String, Object>`. Instead of casting
your way through a tree of `Map<String, Object>` and `List<Object>` by hand, you
ask `Generic` for a value by **path**:

```apex
Generic g = new Generic('{"user":{"name":"Alice","tags":["admin","beta"]}}');
String name = (String) g.get('user.name');      // 'Alice'
String tag  = (String) g.get('user.tags[0]');   // 'admin'
```

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

**Use `Generic` when** you are consuming data whose structure is known at
runtime but awkward to model with classes — integration responses, configuration
blobs, dynamic field maps — and you want safe, readable path access instead of
nested casts and `containsKey` checks.

**Reach for a typed Apex class (or `JSON.deserialize` into one) instead when**
the shape is stable and well-known. A real DTO gives you compile-time safety and
autocomplete; `Generic` trades those away for flexibility. Don't use `Generic`
where a plain `MyResponse` wrapper would do.

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
  into a fresh map (a defensive copy — see [Gotchas](#gotchas-and-testing-notes)).

Everything else operates on that one map.

### 2. Paths are walked recursively

A path like `user.tags[0]` is first **normalized** into a list of segments —
`['user', 'tags', '0']` — then the container walks the tree one segment at a
time. At each step it inspects the current node:

- If the node is a `Map<String, Object>`, the segment is used as a **key**.
- If the node is a `List<Object>`, the segment is parsed as an **integer index**.

`get` returns `null` the moment a segment is missing or an index is out of
bounds, so you never get a `NullPointerException` or `ListException` mid-walk.
`put` is the mirror image: as it walks toward the last segment, it **creates the
intermediate maps it needs**, so `put('a.b.c', x)` works even on an empty
container.

### 3. Coercion and conversion go through JSON

When you ask `get` for a `Type`, simple targets (`Integer`, `Boolean`, `Date`,
etc.) are converted with the matching `valueOf` call. Anything more complex is
handled by a **JSON round-trip** — serialize the raw value, then
`JSON.deserialize` it into the requested type. The same trick powers `sObject()`,
which serializes the whole container and deserializes it into the `SObject` type
you pass. This is why a string value of `'42'` from JSON can come back as a real
`Integer`, and why the map can become an `Account`.

## Public API

`Generic` exposes three constructors, path `get`/`put` methods, conversion
helpers, and two `virtual` extension methods.

> **A note on "properties":** `Generic` has **no public properties**. Its only
> instance state is the `generic` field, which is **`protected`** — visible to
> subclasses but not to outside callers. To read the underlying map from the
> outside, use the `generic()` method. All state changes go through `put`. This
> keeps the container's internals encapsulated behind the path API.

> **A note on access modifiers:** in Apex, a member with **no** access modifier
> is **private**. The `coerce(...)` and `normalizeParths(...)` methods have no
> modifier, so they are private implementation details and are **not** part of
> the public surface — they are described in [How It Works](#how-it-works) only
> to explain behavior.

| Member | Signature | Returns | Description |
| --- | --- | --- | --- |
| Constructor | `Generic()` | `Generic` | Creates an empty container backed by a new `Map<String, Object>`. |
| Constructor | `Generic(String unknown)` | `Generic` | Hydrates the container from a JSON string via `JSON.deserializeUntyped`. The JSON's top level must be an object. |
| Constructor | `Generic(Map<String, Object> unknown)` | `Generic` | Copies the entries of an existing map into a new backing map (defensive copy). |
| `get` | `get(String path)` | `Object` | Returns the raw value at `path`, or `null` if any segment is missing / out of bounds. |
| `get` | `get(String path, Type target)` | `Object` | Returns the value at `path` coerced to `target`. If `target` is `null`, behaves like `get(path)`. See [Type Coercion](#type-coercion). |
| `get` | `get(Object current, List<String> parts, Integer index)` | `Object` | Recursive walker used internally by the two `get` overloads. Public, but you normally call the string overloads. |
| `put` | `put(String key, Object value)` | `void` | Writes `value` at the dotted/bracketed path `key`, creating intermediate maps as needed. |
| `put` | `put(Map<String, Object> paths)` | `void` | Convenience: applies every entry of the map as a `put(path, value)` call. |
| `put` | `put(Object current, List<String> parts, Integer index, Object value)` | `void` | Recursive writer used internally by the other `put` overloads. |
| `json` | `json()` | `String` | Serializes the backing map to a JSON string via `JSON.serialize`. |
| `sObject` | `sObject(Type target)` | `SObject` | Serializes the container and deserializes it into the given `SObject` type. |
| `generic` | `generic()` | `Map<String, Object>` | Returns the backing map directly (live reference, not a copy). |
| `mapping` | `mapping()` (`virtual`) | `Map<String, Object>` | Extension hook. Returns an empty map by default; override in a subclass to declare a shape. |
| `transform` | `transform()` (`virtual`) | `Map<String, Object>` | Builds a new `Generic` from `mapping()` and returns its backing map. See [Subclassing & transform()](#subclassing-and-transform). |

> **About the recursive overloads.** `get(Object, List<String>, Integer)` and
> `put(Object, List<String>, Integer, Object)` are public only because Apex needs
> them visible for the recursion. They are the engine behind the string-based
> overloads — in day-to-day code you call `get(path)`, `get(path, type)`, and
> `put(key, value)`.

## Path Syntax

A path is a `String` that names a location in the nested structure. Before
walking, `Generic` normalizes it: `[` becomes `.`, `]` is removed, and the
result is split on `.`. So all of these describe the same traversal:

| Path | Normalized segments | Walks |
| --- | --- | --- |
| `user.name` | `user`, `name` | map → map key |
| `user.tags[0]` | `user`, `tags`, `0` | map → map → list index 0 |
| `items[1].name` | `items`, `1`, `name` | map → list index 1 → map key |

Rules to keep in mind:

- **Map segments are keys; list segments are indices.** A numeric segment is
  only treated as an index when the current node is actually a `List<Object>`.
- **Missing keys and out-of-range indices return `null`** from `get` — the walk
  stops safely rather than throwing.
- **`put` only descends through maps.** It creates intermediate `Map<String,
  Object>` nodes as it goes; it does **not** create or grow lists. Writing into
  an existing list element by index is not supported by `put`.

## Examples

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

### Hydrate from JSON and read nested values

```apex
Generic g = new Generic('{"user":{"name":"Alice","tags":["admin","beta"]}}');

Assert.areEqual('Alice', g.get('user.name'), 'Reads a nested object value.');
Assert.areEqual('admin', g.get('user.tags[0]'), 'Reads a list value by index.');
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

| `target` | Conversion |
| --- | --- |
| `null` or `Object.class` | Returns the raw value unchanged. |
| `String.class` | `String.valueOf(value)` |
| `Integer.class` | `Integer.valueOf(String.valueOf(value))` |
| `Decimal.class` | `Decimal.valueOf(String.valueOf(value))` |
| `Boolean.class` | `Boolean.valueOf(String.valueOf(value))` |
| `Date.class` | `Date.valueOf(String.valueOf(value))` |
| `Datetime.class` | `Datetime.valueOf(String.valueOf(value))` |
| `List<Object>.class` | Direct cast to `List<Object>`. |
| `Map<String, Object>.class` | Direct cast to `Map<String, Object>`. |
| `List<Map<String, Object>>.class` | Rebuilds each element as a `Map<String, Object>`. |
| Any other `Type` | JSON round-trip: `JSON.deserialize(JSON.serialize(value), target)`. |

> **A `null` value short-circuits.** If the value at the path is `null`,
> coercion returns `null` regardless of `target` — it never tries to convert
> `null`. Combined with the safe-path behavior, `get('missing.path',
> Integer.class)` is `null`, not an exception.

## Subclassing & transform()

`Generic` is declared `virtual`, and `mapping()` / `transform()` are `virtual`
hooks — this is the **Template Method** pattern. The base `mapping()` returns an
empty map; `transform()` simply feeds `mapping()` into a new `Generic` and hands
back its backing map. On the base class both are empty:

```apex
Generic g = new Generic();
Assert.areEqual(0, g.mapping().size(), 'Base mapping() is empty.');
Assert.areEqual(0, g.transform().size(), 'Base transform() is empty.');
```

Subclass `Generic` and **override `mapping()`** to declare a reusable shape.
`transform()` then materializes it for you — useful for building a canonical
output structure (for example, normalizing an inbound payload into the map your
downstream code expects):

```apex
public class StatusReport extends Generic {
  public override Map<String, Object> mapping() {
    return new Map<String, Object>{
      'status'  => 'ready',
      'version' => 1
    };
  }
}

Map<String, Object> result = new StatusReport().transform();

Assert.areEqual('ready', result.get('status'), 'transform() uses mapping() output.');
Assert.areEqual(1, result.get('version'), 'Numeric values are preserved.');
```

A typical subclass would read inbound data in `mapping()` (via `get(...)` on
`this`) and assemble the target shape, keeping the transformation logic in one
named, testable place.

## Gotchas & Testing Notes

- **The string JSON constructor expects a top-level object.** `new
  Generic(json)` casts the deserialized result to `Map<String, Object>`. JSON
  whose root is an array or a scalar will throw a cast exception — wrap it in an
  object first.
- **`get` is null-safe; coercion can still throw.** The path walk never throws on
  missing data, but converting an incompatible value can — e.g.
  `get('name', Integer.class)` on a non-numeric string raises a
  `TypeException`. Coerce only values you expect to fit the target.
- **`put` builds maps, not lists.** Writing `a.b.c` creates the intermediate
  maps, but `put` cannot create list elements or set an item by index. To write
  into a list, build the list and `put` it as a whole value.
- **`generic()` returns a live reference.** It hands back the actual backing map,
  not a copy — mutating the returned map mutates the container. The `Map`
  *constructor*, by contrast, copies its input, so later changes to the source
  map do **not** leak in:
  ```apex
  Map<String, Object> source = new Map<String, Object>{ 'status' => 'initial' };
  Generic g = new Generic(source);
  source.put('status', 'changed');           // mutates source only
  Assert.areEqual('initial', g.get('status'), 'Constructor took a defensive copy.');
  ```
- **`sObject()` is only as valid as your keys.** Deserialization into an SObject
  succeeds only when keys map to real field API names of the correct types;
  mismatches throw during deserialization. It's a great way to fabricate records
  for tests — but, like any deserialized SObject, those records carry whatever
  values you put in, including normally read-only ones, so keep them on the
  mocking side of your tests, not for DML.
- **Numeric path segments are indices only inside lists.** `tags[0]` walks a
  list, but if `tags` happens to be a map, `0` is treated as the literal key
  `'0'`. The segment's meaning depends on the node type at that point in the walk.
- **Coercion reads, it does not store.** `get(path, type)` returns a converted
  copy; it does not change what's stored in the container. The backing map keeps
  the original raw value.
- **Don't reach for the recursive overloads.** `get(Object, List<String>,
  Integer)` and the four-argument `put` exist for internal recursion. Use the
  string-path overloads; the recursive ones expect already-normalized segment
  lists and a starting index.
