---
layout: ../layouts/DocsLayout.astro
title: REST | sf-bedrock docs
description: Metadata-routed Apex REST endpoints with versioning, context parsing, and self-contained sub-endpoint classes.
eyebrow: Frameworks
heading: REST
lede: REST gives Bedrock one Apex REST gateway at /services/apexrest/api and routes versioned endpoint roots from Rest_Config__mdt into Apex classes that extend Rest.
sections:
  - label: Overview
    href: "#overview"
  - label: Quickstart
    href: "#quickstart"
  - label: Examples
    href: "#examples"
  - label: Routing
    href: "#routing"
  - label: Settings
    href: "#settings"
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

`Rest` is a small routing layer over Apex REST. A single gateway listens at
`/services/apexrest/api/*`, reads `Rest_Config__mdt`, builds a `Rest.Request`,
and calls the matching `Rest` subclass.

**Use `Rest` when** you want versioned API endpoints whose root mappings live in
metadata, while endpoint behavior stays in focused Apex classes.

**Reach for a direct `@RestResource` class instead when** an endpoint is a
one-off integration with no shared routing, versioning, settings, or
sub-endpoint needs.

## Quickstart

Create an endpoint class that extends `Rest` and override the HTTP methods it
supports.

```apex
public inherited sharing class AccountRest extends Rest {
    public override void get(Rest.Request request) {
        respond(new Map<String, Object> {
            'accountId' => request.primaryId
        });
    }
}
```

Create one `Rest_Config__mdt` record:

| Field | Value |
| --- | --- |
| `Active__c` | `true` |
| `Route__c` | `accounts` |
| `Version__c` | `1` |
| `Apex__c` | `AccountRest` |

Then call:

```text
/services/apexrest/api/v1/accounts/001000000000001AAA
```

## Examples

### Add a sub-endpoint

Sub-endpoints are inner classes that also extend `Rest`.

```apex
public inherited sharing class AccountRest extends Rest {
    public class Contacts extends Rest {
        public override void get(Rest.Request request) {
            respond(new Map<String, Object> {
                'accountId' => request.primaryId,
                'contactId' => request.secondaryId
            });
        }
    }
}
```

That class handles:

```text
/services/apexrest/api/v1/accounts/001000000000001AAA/contacts/003000000000001AAA
```

### Read query params, body, and bulk ids

`params` is only the query string. `body` is only the JSON object body. `ids` is
a convenience set populated from `?ids=...` or body `ids`.

```apex
public override void post(Rest.Request request) {
    Set<Id> ids = request.ids;
    String include = request.params.get('include');
    Object records = request.body.get('records');

    respond(202, new Map<String, Object> {
        'accepted' => ids.size(),
        'include' => include,
        'hasRecords' => records != null
    });
}
```

### Gate access in Apex

Override `canAccess` for endpoint-owned permission rules.

```apex
public override Boolean canAccess(Rest.Request request) {
    return FeatureFlag.isEnabled('api.accounts.enabled');
}
```

## Routing

The gateway URL shape is:

```text
/services/apexrest/api[/vN]/{root}[/{segment1}[/{segment2}[/{segment3}]]]
```

`Rest_Config__mdt.Route__c` owns the root segment. The version segment is
optional; when it is absent, `Rest` uses the highest active version for that
route.

After the root, these shapes are supported:

| Shape | Meaning |
| --- | --- |
| `/accounts` | root endpoint |
| `/accounts/{primaryContext}` | root endpoint with context |
| `/accounts/contacts` | `Contacts` sub-endpoint |
| `/accounts/{primaryContext}/contacts` | context plus sub-endpoint |
| `/accounts/contacts/{primaryContext}` | sub-endpoint plus context |
| `/accounts/{primaryContext}/contacts/{secondaryContext}` | context, sub-endpoint, secondary context |

Sub-endpoint resolution wins over context. If `contacts` resolves to an inner
`Contacts` class, it is treated as a sub-endpoint, not a context value.

## Settings

`Rest_Settings__c` is a hierarchy custom setting. Blank or invalid values fall
back to safe defaults.

| Field | Default behavior |
| --- | --- |
| `Unknown_Route_Status_Code__c` | `404` |
| `Inactive_Route_Status_Code__c` | `404` |
| `Unsupported_Method_Status_Code__c` | `405` |
| `Access_Denied_Status_Code__c` | `403` |
| `Expose_Error_Details__c` | `false` |

## Testing

Use `RestMock` to seed route metadata and settings in memory.

```apex
@istest static void testAccountRoute_returnsAccountResponse() {
    Rest.setMock(new RestMock().seedConfigs(new List<Rest_Config__mdt> {
        new Rest_Config__mdt(
            Active__c = true,
            Route__c = 'accounts',
            Version__c = 1,
            Apex__c = 'AccountRest'
        )
    }));

    RestRequest request = new RestRequest();
    request.httpMethod = 'GET';
    request.requestURI = '/services/apexrest/api/v1/accounts';
    RestContext.request = request;
    RestContext.response = new RestResponse();

    RestGateway.doGet();

    Assert.areEqual(200, RestContext.response.statusCode, 'Expected the account route to resolve.');
}
```

## How It Works

Three ideas explain everything `Rest` does.

**One: metadata resolves only the root.** `Rest_Config__mdt` chooses the first
endpoint class by route and version. Endpoint classes own their sub-endpoints.

**Two: the request is positional.** The router exposes generic
`primaryContext`, `secondaryContext`, `primaryId`, and `secondaryId` values.
Endpoint classes can wrap those with semantic helper methods when useful.

**Three: response writing stays in Apex.** Endpoint methods return `void`.
They call `respond` or `error`, which writes to `RestContext.response`.

## Public API

Most app code extends `Rest` and overrides the method it needs.

| Member | Signature | Description |
| --- | --- | --- |
| `get` | `public virtual void get(Rest.Request request)` | Handles GET; default returns method-not-allowed. |
| `post` | `public virtual void post(Rest.Request request)` | Handles POST; default returns method-not-allowed. |
| `put` | `public virtual void put(Rest.Request request)` | Handles PUT; default returns method-not-allowed. |
| `patch` | `public virtual void patch(Rest.Request request)` | Handles PATCH; default returns method-not-allowed. |
| `del` | `public virtual void del(Rest.Request request)` | Handles DELETE; default returns method-not-allowed. |
| `canAccess` | `public virtual Boolean canAccess(Rest.Request request)` | Endpoint access hook; defaults to `true`. |
| `respond` | `protected void respond(Object body)` | Writes a JSON `200` response. |
| `respond` | `protected void respond(Integer statusCode, Object body)` | Writes a JSON response with the given status. |
| `error` | `protected void error(Integer statusCode, String message)` | Writes a JSON error response. |

`Rest.Request` exposes `version`, `route`, `segments`, `primaryContext`,
`secondaryContext`, `primaryId`, `secondaryId`, `ids`, `body`, and `params`.

`RestMock` exposes `seedConfigs(List<Rest_Config__mdt>)` and
`seedSettings(Rest_Settings__c)` for tests.

## Notes & Edge Cases

- Duplicate active `Rest_Config__mdt` records for the same route and version
  return a framework configuration error instead of picking one.
- `Route__c` is a static root segment, not a regex.
- `Version__c` is matched from URL segments like `v1`, `v2`, and `v10`.
- JSON bodies that are blank or not JSON objects produce an empty `body` map.
- Query `ids` win over body `ids` when both are present.
- Sub-endpoint class names are derived from the path segment, so `line-items`
  resolves to an inner `LineItems` class.
