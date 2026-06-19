# sf-bedrock Roadmap

This file is only the cross-component index. The implemented contract lives in
`force-app/bedrock/lib`; per-component guides describe current behavior, and
per-component roadmaps track remaining work.

Treat roadmap notes as intended direction, not public API. Inspect the current
source before building, and ask before locking names, schemas, metadata objects,
or behavior that does not exist yet.

## Cross-Cutting Principle

Treat a thread as a container of ordered work. Work created while a thread is
running should stay on that thread unless a future design explicitly breaks it
out. Async and EventRelay keep their own work-item objects and policies, but
they share the same `Thread__c` lifecycle so chained work remains easy to reason
about.

Extend mocks and service override surfaces only when a concrete test needs a new
seam. Keep the exposed levers intentionally light.

## Component Roadmaps

| Component | Roadmap | Current purpose |
|---|---|---|
| Async | [`lib/async/ROADMAP.md`](force-app/bedrock/lib/async/ROADMAP.md) | Remaining Async enhancements and console follow-up |
| Thread | [`lib/thread-service/ROADMAP.md`](force-app/bedrock/lib/thread-service/ROADMAP.md) | Shared recovery, pool policy, and operator visibility |
| Limiter | [`lib/limiter/ROADMAP.md`](force-app/bedrock/lib/limiter/ROADMAP.md) | Remaining org-health integration ideas |
| Scheduler | [`lib/scheduler/ROADMAP.md`](force-app/bedrock/lib/scheduler/ROADMAP.md) | Future cadence, throttling, and admin visibility work |
| EventRelay | [`lib/event/ROADMAP.md`](force-app/bedrock/lib/event/ROADMAP.md) | Remaining event framework decisions |
| Selector | [`lib/selector/ROADMAP.md`](force-app/bedrock/lib/selector/ROADMAP.md) | Future query and cache abstraction |
