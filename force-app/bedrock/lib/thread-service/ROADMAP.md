# ThreadService & Multithreading — Roadmap

Shared concurrency infrastructure beneath thread-based work (`Async` today,
future `Event`). The current implementation is described in `./AGENTS.md`; this
file tracks remaining proposed work. Cross-cutting roadmap principles and
feature sequencing live in the repo root `ROADMAP.md`.

`Thread` and `Thread__c` are deliberately *shared* infrastructure
(like `Limiter` in `../limiter/ROADMAP.md`). `Async`
(`../async/ROADMAP.md`) and the future `Event` framework
(`../event/ROADMAP.md`) are both consumers; their work items can share a thread
so chained work stays linear and understandable.

These are intended designs, not finalized public APIs. Ask before locking
names, schemas, metadata objects, or behavior that does not exist yet.

## Multithreading — per-user thread cap + backlog handoff

Status: core cap + handoff is implemented for `Async` through `Thread__c`.
Backlog starvation recovery is **blocked by Scheduler MVP1**
(`../scheduler/ROADMAP.md` — the 15-minute monitor). Event integration and
Limiter integration remain future work.

Today the framework runs effectively one logical thread per originating
transaction: work is tagged with a `threadId` (`Thread__c`) and a single
Queueable chain drains it serially. This feature makes concurrency explicit — a
user may run up to N worker threads at once, each draining its own partition of
work, with idle threads recycling to launch other backlogged threads.

**Concept:** a *thread* is one live Queueable chain plus the `Async__c` work
items that share its `threadId`. A `Thread__c` record is the persisted
representation of a thread and carries its own `Status__c`. The cap is
a **soft** maximum of concurrently active threads per user — a suggestion, not a
guarantee. Under very high volume it may overshoot by a job or two, which is
acceptable. What the design *does* guarantee is that work on a thread runs
reliably and that available limits are used as fully as possible to maximize
throughput.

**Thread service (shared infrastructure):** the source of truth for threads —
it mints the `threadId`, creates and queries `Thread__c` records, and owns
thread `Status__c` transitions. Because **Event also needs thread records**,
this is a standalone injectable service like `Limiter` — *not* an `Async`
inner class. Async and Event are both consumers; the concurrency mechanism (soft
cap, `FOR UPDATE` spin-up coordination, backlog handoff) lives in one place.
It sits beside `WorkService` (which owns `Async__c` work-item lifecycle): a
thread groups work, so the concepts overlap, but thread lifecycle warrants its
own shared service.

**Why work items never race:** every processing chain starts from `AsyncThread`
with an explicit `threadId` passed down the entire chain. `Async__c` work items
are partitioned by `threadId` and only one chain ever owns a given thread, so
there is no claim race on the work items themselves. The only contention is
*which thread to spin up next*, resolved on `Thread__c` with short
`FOR UPDATE` locks — captured and released quickly so new threads start fast,
accurately, and without collisions.

**Behavior:**

- New per-user setting `Max_Threads__c` (`Async_Settings__c`) suggests the
  concurrency cap for a user, scoped by `CreatedById` — the framework runs in
  the user's context, so no separate owner field is needed. The cap counts
  running `Thread__c` records for that user. The **recommended org default is
  `1`** — no multithreading unless deliberately opted into. Heavy automation
  and service identities (`AutomatedProcessUser`, integration/service accounts)
  are the intended place to raise it via per-user overrides — let those rip.
- **On enqueue (synchronous transaction):** stage the work under a
  `Thread__c`, then spin up the thread when the current user has a free slot.
  A synchronous Apex
  transaction may enqueue up to 50 Queueables, so each new transaction is an
  opportunity to fan out. A Queueable context can enqueue only one child, so
  fan-out happens at synchronous boundaries; within a chain the pool grows only
  by recycling (below).
- **No slot available:** do nothing — the thread's `Thread__c` stays in
  backlog (`Pending`) until a slot frees up or recovery picks it up.
- **Backlog handoff ("look over your shoulder"):** when a chain's finalizer
  drains its own thread, before dying it queries `Thread__c`
  `FOR UPDATE` for a backlogged thread, claims it, and launches that chain. Live
  threads settle at `min(cap, threads available)`.
- **Backlog starvation recovery (blocked by Scheduler MVP1):** if a
  `Thread__c` sits in backlog longer than ~15 minutes, the scheduled
  system monitor launches it — and as many other backlogged threads as its
  limits allow. This is the one path that does not run in the originating user's
  context.
- **Composes with Limiter:** a thread starts only when both a slot is
  available AND `Limiter.isSafe()`. The cap is per-user concurrency;
  Limiter is org health. (Limiter is itself blocked by Scheduler
  MVP1, so the cap can ship first and gain the safety gate later.)

**Schema:** `Thread__c` (`Status__c`, `Pool__c`, `Thread_Key__c`, unique
`Lane_Key__c`; `CreatedById` scopes per-user caps). `Lane_Key__c` is the
implemented uniqueness decision for `Pool__c + Thread_Key__c`: callers store a
readable combined key in one unique text field because Salesforce does not
offer compound uniqueness for two custom text fields. The existing
`Async__c.Thread__c` lookup associates work items with their thread. The link
from work item to thread is a **plain lookup, not master-detail**: master-detail
would let a `FOR UPDATE` on a `Thread__c` lock its child work-item rows,
risking exactly the kind of claim contention this design avoids.
Future Event support should preserve the same thread container. If Async work
creates Event work, the Event work should stay on the same thread and may run
ahead of lower-urgency Async work on that thread.

**Open design questions:**

- How Event work is prioritized ahead of Async work while preserving the linear
  thread model.
- Whether the 15-minute starvation-recovery monitor is the same job as the
  Limiter resume monitor or a sibling. **Deferred until Scheduler MVP1** —
  the answer isn't needed before then, and could land either way.
