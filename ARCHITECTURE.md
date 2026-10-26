# Architecture

SwiftUI views share DashboardModel for live state, navigation, selections, scan progress, approvals, results and aggregate history.

```text
SwiftUI views → DashboardModel
                 ├─ SystemMetricsProvider → Mach / sysctl / libproc / AppKit
                 ├─ DiagnosisEngine → configurable rules / sustained samples / snoozing
                 ├─ SafeStorageScanner → cache identity + metadata inventory
                 ├─ FileDiscoveryService → size groups / quick samples / streaming hash / byte verification
                 └─ ActionExecutor → comparable observations + approved action queue
                                      ├─ GracefulApplicationQuitter
                                      ├─ TrashService → FilePathPolicy / pinned staging / Foundation Trash
                                      └─ DeveloperProcessService → validated graceful SIGTERM
Developer Tools → DeveloperInspectionService → bounded fixed-argument local CLI checks
Aggregate outcomes → ActivityStore → local UserDefaults / newest 100 records
```

Scans and hashing run on cancellable utility tasks with bounded buffers. The model and AppKit application access stay on the main actor. Standalone developer process inspection is actor-isolated and on demand. The monitoring loop keeps a bounded in-memory trend and slows under critical thermal state.

File enumeration has one owner. `BoundedScanWork` schedules a bounded structured task group (two workers by default, a hard ceiling of four). Sampling and full hashing parallelize per file; exact comparison parallelizes independent digest buckets, preserving order within each bucket. Result order and suggested keepers are deterministic. Dynamic limit reductions drain existing readers before scheduling additional work; buffers are bounded per worker, never proportional to file size.

`ScanProgressReporter` merges cumulative counters on an actor and serializes awaited callbacks with an asynchronous FIFO gate. No semaphore blocks a cooperative thread. Parent cancellation reaches the detached coordinator and every child; in-progress reads check cancellation between bounded chunks. UI updates are throttled separately from scanner correctness.

`ScanFingerprintCache` stores only sample/full-hash strings and complete filesystem stamps in an actor, with bounded LRU eviction and a 10-minute reuse lifetime. Each scan receives an immutable snapshot; expired entries are pruned when a snapshot is requested. Every hit still validates an open descriptor and ancestors; comparison never trusts a cached equality result. Cache reuse is disabled for unknown, external/removable or nonlocal volumes. User disabling clears cache memory; nothing is persisted. Files are revalidated again after awaited callbacks and before final duplicate results.

Every approved mutation goes through ActionExecutor. It captures two interval CPU samples over comparable windows before and after execution, and reports actual memory/swap/process-count/storage observations. Relevant-volume storage is measured when file actions target another volume. Missing measurements remain unavailable.

TrashService revalidates filesystem ownership, ancestors, identity, cache revision and duplicate keeper before moving a selected item. It uses descriptor-pinned staging and a no-overwrite restore path for errors. File scans preserve the authorized root in every candidate. GUI-app identity includes launch date; CLI identity includes UID, kernel start time and exact executable path.

ActivityStore persists aggregate operation type/status/count/estimated bytes/capacity delta only. Paths, process names, command arguments and scan results are not persisted. Services and model dependencies can be injected so integration tests exercise complete approval flows using generated fixtures.
