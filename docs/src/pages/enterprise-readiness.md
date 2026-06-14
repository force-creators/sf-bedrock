---
layout: ../layouts/DocsLayout.astro
title: Enterprise Readiness | sf-bedrock docs
description: Governance, security, distribution, API support, and scale guidance for adopting sf-bedrock in enterprise Salesforce orgs.
eyebrow: Adoption
heading: Enterprise Readiness
lede: Bedrock is source-first and intentionally small. Enterprise adoption should be explicit about security posture, supported APIs, operations ownership, and rollout boundaries.
sections:
  - label: Distribution Model
    href: "#distribution-model"
  - label: Security & Sharing
    href: "#security-and-sharing"
  - label: Supported API Surface
    href: "#supported-api-surface"
  - label: Scale Language
    href: "#scale-language"
  - label: Ownership Boundaries
    href: "#ownership-boundaries"
  - label: Readiness Checklist
    href: "#readiness-checklist"
---

## Distribution Model

Bedrock is currently source-first. It is intended for teams that are comfortable
reviewing Apex framework code directly, deploying the pieces they need, and
owning that source in their Salesforce delivery process.

Packaging and public distribution options are still being evaluated. Until a
package strategy is formalized, teams should document which source folders are
required, which metadata each framework uses, and which tests prove a deployment
is healthy.

## Security & Sharing

Bedrock does not replace Salesforce security design. Application code still owns
the security boundary.

Use `with sharing` or `inherited sharing` in examples and application classes
unless there is a deliberate reason to do otherwise. Bedrock seams like `DML`,
`Query`, `RecordBuffer`, `Async`, and `Scheduler` make code more testable and
operable; they do not automatically enforce row-level sharing, CRUD, or FLS.

Document security decisions where they matter:

- UI controllers should stay thin and enforce the boundary expected by the
  component.
- Services should use a sharing mode that matches the business operation.
- System-mode automation should be intentional and reviewable.
- Console and operations users should receive only the permissions they need to
  monitor, retry, delete, configure, or troubleshoot framework records.

## Supported API Surface

Bedrock keeps subscriber-facing APIs intentionally small. Because the framework
is source-first, some members may need broader Apex visibility than they would
have in a managed package with a namespace. The docs define what is supported
for application teams.

Use these labels when documenting APIs:

| Label | Meaning |
| --- | --- |
| Subscriber-facing API | Intended for application teams to call from normal code. |
| Extension seam | Intended to be overridden, replaced, or subclassed only where the docs say so. |
| Test seam | Intended for tests, mocks, or framework verification. |
| Framework internal | Technically visible because of Apex or source distribution constraints, but not a compatibility promise. |

When in doubt, application teams should treat the Public API section of each
library page as the supported contract and avoid framework internals.

## Scale Language

Bedrock's design comes from large-org automation problems: governor limits,
async fan-out, test speed, trigger hygiene, and operational recovery. Its roots
are battle-tested in Fortune 100-scale Salesforce environments.

Public benchmark numbers are not published yet. Until they are, use bounded
language:

- Describe the platform limit or operational pressure being addressed.
- Explain the design tradeoff Bedrock makes.
- State current hardening gaps honestly.
- Avoid implying a specific throughput number unless it has been measured and
  can be reproduced.

Good scale documentation earns trust by saying what the framework does, where it
expects the team to tune it, and what still belongs on the roadmap.

## Ownership Boundaries

Decide ownership before production rollout.

| Area | Typical owner |
| --- | --- |
| Service and domain code | Application development team |
| Library source and upgrades | Platform engineering or architecture team |
| Console monitoring | Admin, support, or platform operations team |
| Async and scheduler configuration | Platform engineering with admin visibility |
| Permission sets and access | Salesforce admin or security owner |
| Production incident response | Team that owns the affected automation |

These are defaults, not rules. The important part is that each org chooses an
owner before operators need one.

## Readiness Checklist

Before a public pilot, confirm:

- The pilot has one clear use case and one accountable owner.
- Required source folders and metadata are listed.
- Examples use `with sharing` or `inherited sharing` where appropriate.
- CRUD, FLS, and sharing responsibilities are documented.
- Subscriber-facing APIs are separated from framework internals.
- Permissions for admin and operator workflows are understood.
- Async or scheduler pilots include monitoring and recovery expectations.
- Current gaps are labeled as current behavior, operating practice, or roadmap.
