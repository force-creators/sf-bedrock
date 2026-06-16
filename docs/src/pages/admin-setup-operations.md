---
layout: ../layouts/DocsLayout.astro
title: Admin Setup & Operations | sf-bedrock docs
description: Operational guidance for admins, release managers, and support teams who monitor and recover sf-bedrock runtime frameworks.
eyebrow: Operations
heading: Admin Setup & Operations
lede: Bedrock is code-first, but production work still needs owners. Admins and operators need clear monitoring, recovery, permission, and limit guidance before runtime frameworks go live.
sections:
  - label: Who Owns What
    href: "#who-owns-what"
  - label: Setup Checklist
    href: "#setup-checklist"
  - label: Permission Model
    href: "#permission-model"
  - label: Console Workflows
    href: "#console-workflows"
  - label: Troubleshooting
    href: "#troubleshooting"
  - label: Current Limits
    href: "#current-limits"
---

## Who Owns What

Bedrock works best when operations ownership is explicit.

| Responsibility | Typical owner |
| --- | --- |
| Deploying Bedrock source | Platform engineering or release team |
| Assigning permissions | Salesforce admin or security owner |
| Monitoring Console views | Admin, support, or platform operations |
| Fixing failed subscriber logic | Development team that owns the class |
| Changing async or scheduler configuration | Platform engineering with admin review |
| Deciding retry, delete, or rollback actions | Operations owner and application owner |

The exact names can differ by org. The important part is that a failed job has a
known path from operator to code owner.

## Setup Checklist

Before a production rollout, document the setup steps for the specific Bedrock
libraries in use. Source-first installs do not yet ship a universal permission
set, so each org should turn the selected source folders into a local deploy and
access checklist.

For a code-only pilot with `TestData`, `DML`, or `Query`:

- Deploy the required Apex classes and tests.
- Run the focused test class or method that proves the pilot.
- No admin console setup is required.

For runtime frameworks like `Async` or `Scheduler`:

- Deploy the framework classes, triggers, objects, fields, custom settings, and
  metadata types used by that runtime.
- Deploy any console metadata the team wants operators to use.
- Create or review required custom metadata and custom setting rows.
- Assign object, field, tab, app, and Apex class access to the right users.
- Confirm the Scheduler heartbeat is installed when using scheduled jobs.
- Document who monitors errors and backlog after release.

## Permission Model

Use least-privilege permission groups. A future package may provide starter
permission sets, but source-first teams should still decide which users need
which capabilities.

| Role | Typical access |
| --- | --- |
| Read-only operator | View Console pages, runtime records, statuses, errors, and configuration. |
| Recovery operator | Read-only access plus retry or delete permissions for failed work where allowed. |
| Configuration owner | Access to custom metadata, custom settings, and scheduler or async configuration. |
| Developer | Apex class visibility, tests, and source access through the normal delivery process. |
| Admin | Permission assignment, app/tab access, and setup visibility. |

Retry and delete actions should be reserved for users who understand the
business effect of rerunning or removing work.

## Console Workflows

The Console should answer operational questions quickly:

![Bedrock Console Async tab with operational summary cards and async work subtabs.](/images/bedrock-console-async.png)

- What work is waiting?
- What failed?
- Which job type failed?
- What error message and stack trace were saved?
- Is a scheduler job enabled, due, stale, or failing?
- Are archive or settings views showing growth that needs attention?

Use the Console as an operations window. Do not build business logic around the
Console controllers. Application behavior belongs in services, subscribers, and
metadata-backed framework contracts.

The Scheduler view gives operators a chronological schedule surface for runtime
rows and configured jobs.

![Bedrock Console Scheduler tab with enabled, due-now, error, and disabled cards plus a schedule timeline.](/images/bedrock-console-scheduler.png)

## Troubleshooting

Start with the symptom, then route to the owner.

| Symptom | First check | Likely owner |
| --- | --- | --- |
| Async backlog is growing | Running thread count, pending work age, `Thread_Settings__c.Max_Threads__c` | Platform operations |
| Async errors are growing | Error message, stack trace, subscriber class | Application development team |
| Work is stuck as `Running` | Recent platform incidents, aborted jobs, finalizer behavior | Platform engineering |
| Scheduler job did not run | Heartbeat installed, job enabled, next run time, error message | Admin and platform engineering |
| Archive or runtime data is growing | Archive settings, cleanup configuration, retention expectation | Platform operations |
| Console action is unavailable | Object, field, tab, class, or app permission | Salesforce admin |

When the framework records an error, treat the saved message and stack trace as
the starting point. If the failure belongs to subscriber code, fix that class and
retry only when rerunning the work is safe.

## Current Limits

Some operational hardening belongs in current practice, and some belongs on the
roadmap.

Current behavior:

- Async records failed work with error message and stack trace.
- Async supports bounded auto-retry when configured.
- Manual retry is an operator workflow, not a direct object-editing recipe. Use
  the Console where retry actions are available and permissions allow them.
- Scheduler status lives in runtime rows and updates on the heartbeat.

Recommended operating practice:

- Monitor backlog, errors, and scheduler health after production rollout.
- Keep retry/delete permissions narrow.
- Assign a code owner to every subscriber or scheduled job class.
- Document recovery steps for each business-critical job.

Roadmap or hardening area:

- Automated stuck-running recovery is not yet a complete public contract.
- Packaged permission sets are not yet the source-first install model.
- Public benchmark and capacity guidance should be added when measured.
