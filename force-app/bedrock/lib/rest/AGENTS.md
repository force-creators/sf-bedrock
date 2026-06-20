# REST — Agent Guide

Component guide for the `Rest` library. Global conventions (Apex style,
testing rules, Salesforce MCP deploy/validate workflow, architecture layers)
live in the repo root `AGENTS.md`. Inspect the code in this folder before
depending on exact method behavior.

## What it is

`Rest` is a metadata-routed Apex REST framework. One gateway is mounted at
`/services/apexrest/api/*`, root routes are resolved from `Rest_Config__mdt`,
and endpoint classes extend `Rest` to handle HTTP methods and optional
sub-endpoints.

## Current shape

- `RestGateway` owns the `@RestResource(urlMapping='/api/*')` entry point.
- `Rest_Config__mdt` maps a root route and version to one `Rest` subclass.
- `Rest_Settings__c` is a hierarchy custom setting for default REST status
  codes and framework error exposure.
- URL versions use `/vN/root`; when omitted, the active route marked
  `Default__c` is used. If no active default is configured, the highest active
  route version is used.
- Sub-endpoint resolution always wins over context. Supported endpoint shapes
  after the root are no segment, one context or sub-endpoint, context plus
  sub-endpoint, sub-endpoint plus context, and context plus sub-endpoint plus
  secondary context.
- `Rest.Request` separates `params` (query string), `body` (JSON object), and
  `ids` (bulk Id convenience set).

## Schema

The implemented schema is `Rest_Config__mdt` with `Active__c`, `Default__c`,
`Route__c`, `Version__c`, and `Apex__c`; and `Rest_Settings__c` with
configurable fallback status codes and error detail exposure.
