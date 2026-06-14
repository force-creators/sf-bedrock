# sf-bedrock docs — authoring template

This is the canonical structure for every **library reference page** under
`docs/src/pages/*.md` (the per-tool pages: TestData, DML, Query, PlatformCache,
RecordBuffer, TriggerHandler, FeatureFlag, Generic, Async, Pluck, …). The
landing page (`index.astro`) and `getting-started.astro` are marketing/onboarding
and are out of scope for this template.

The goal: a junior-to-mid Salesforce developer should be able to **start building
within the first screen**, and circle back later for mechanism and reference.
Every page must therefore lead with usage and keep internals/reference below the
fold. The first three and last sections are identical on every page, so the
reader always knows where they are.

## Audience & voice

- **Primary reader:** junior-to-mid Salesforce developers. Seniors will read too
  and we give them the depth — but it lives lower on the page, not up top.
- **Get them to understanding and building first.** Framework philosophy and
  "why we designed it this way" go at the end, in an aside/callout, or in a
  dedicated lower section — never in the opening.
- **No embellishment.** State what the tool does plainly. Don't oversell.
- **Match the repo's Apex style** (see `AGENTS.md`): minimalist, low-ceremony,
  human-readable, self-documenting, no abbreviations. Sparse, useful comments.
- **Every API claim must be verified against the actual class** in
  `force-app/bedrock/lib/<tool>` before it ships. Do not describe behavior,
  signatures, or access modifiers you have not confirmed in the source. If
  something is genuinely uncertain, say so rather than guessing.

## Apex example rules

- Examples must be realistic and copy-pasteable, and must plausibly compile.
- Follow repo test conventions when showing tests: lowercase `@istest`, the
  `Assert` class (never `System.assert*`), **every assertion carries a meaningful
  message**, and build records with `TestData` (calling `mockIds()` by default
  when Ids are needed). DML through `DML`, queries through `Query.records(...)`.
- Bulk-safe by default: query once per batch, never SOQL/DML inside a per-record
  loop.

## Frontmatter contract

```yaml
---
layout: ../layouts/DocsLayout.astro
title: <ClassName> | sf-bedrock docs
description: <one sentence, used for SEO/meta>
eyebrow: <the nav group label: Foundation API | Dependency Injection | Automation | Frameworks | Other>
heading: <ClassName>
lede: <1–2 sentences: what it is + the concrete win. No fluff.>
sections:
  - label: Overview
    href: "#overview"
  # ...one entry per H2 below, in the exact order they appear on the page
---
```

- `sections` **must list every H2 in page order** — it drives both the in-page
  "On this page" rail and the sidebar sub-nav. Keep it in sync with the headers.
- `eyebrow` is exactly the tool's nav-group label.

## The fixed spine (H2 order)

Every page uses these H2s, in this order. The first three and the last are
mandatory and identically named on every page; the middle band is where
tool-specific sections live.

1. **`## Overview`** — what problem it solves and **when to use it / when not**.
   Keep the existing, well-loved pattern: a short "**Use `X` when…**" and
   "**Reach for … instead when…**" pair. Short. No mechanism yet.

2. **`## Quickstart`** — the single smallest end-to-end snippet that makes the
   tool productive. One or two short code blocks. This is the "get building"
   moment. (For Async this is the two-step extend-and-`enqueue` contract; for
   DML it's "call `DML.insertRecords(records)` instead of `insert records;`".)

3. **`## Examples`** — progressive, realistic snippets, simple → real, ideally
   ending in a realistic service/unit example.

   - **Tool-specific usage band (optional):** sections that are core to *using*
     this particular tool slot in right here, after Examples, named per tool —
     e.g. `## Path Syntax`, `## Type Coercion` (Generic); `## Relationships`,
     `## Read-Only & System Fields`, `## Mock Ids` (TestData);
     `## Wiring Into a Trigger`, `## Buffered DML` (TriggerHandler);
     `## Contexts & Nested Flushes`, `## Reading Staged Records` (RecordBuffer);
     `## Configuration` (Async); `## Where Flag Values Come From` (FeatureFlag).
     These are the allowed deviations. They live in this one predictable band.

4. **`## Testing`** — the mock / test-seam path and the assertion shape. Name the
   mock in prose (e.g. "with `DMLMock`"), **not** in the header. For tools that
   *are themselves* test utilities (e.g. TestData) and have no separate mock,
   this section may be folded into Examples and omitted — but say so by making
   the realistic test the last Example, so the spine still reads predictably.

5. **`## How It Works`** — the mechanism walkthrough. Keep the proven
   "**Three ideas explain everything `X` does**" device where it fits. This is
   the circle-back layer; it sits **below** usage on purpose.

6. **`## Public API`** — the reference table(s): members, signatures, returns,
   descriptions; inner types; the test-only methods. Keep the established
   "**A note on access modifiers**" / "**A note on 'properties'**" asides — in
   Apex, no access modifier means private, and that's worth stating. Async needs
   this table added; it currently lacks one.

7. **`## Notes & Edge Cases`** — **always the last section.** The bulleted list of
   edge behavior, pitfalls, and testing reminders. (This replaces the old
   "Gotchas & Testing Notes" / "Gotchas & Notes" headers — do not use the word
   "gotcha".)

## What to keep from the current pages

These conventions are good and should survive the rewrite, just relocated into
the slots above:

- The "Use `X` when / Reach for … instead when" framing (→ Overview).
- The "Three ideas explain everything `X` does" device (→ How It Works).
- The access-modifier / "no public properties" notes (→ Public API).
- Blockquote `>` asides for the one philosophical or "why" note per concept —
  this is where deeper rationale belongs, kept brief.
