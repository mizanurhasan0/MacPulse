# Feature status

| Area | Status |
| --- | --- |
| Dashboard and responsive UI | Live CPU, VM memory estimates, swap usage, storage, thermal state, and recent CPU/memory trends |
| Languages and theme | English, Bangla, Arabic RTL; System/Light/Dark plus four saved accent palettes |
| Recommendations | Sustained CPU, low storage, memory availability and thermal rules; one-hour snooze and restore |
| Smart Boost | Measures state, scans caches, builds an optional app/cache plan, requests confirmation, executes approved actions, and reports actual outcomes and before/after measurements |
| App quit | Confirmed graceful request with PID, bundle, executable and launch-date revalidation; observes termination; never force-quits |
| Cache analysis and cleaning | Sizes immediate user cache folders; manual selection, path preview and confirmed move to Trash; active-app, system-managed, unidentified, incomplete and changed caches are excluded |
| Large files | Explicitly chosen folder, fast metadata-only scan, saved size threshold, size sorting, type/date/path, Finder reveal, manual selection and confirmed Trash |
| Duplicates | Size grouping, small beginning/end samples, streaming SHA-256, exact byte comparison, hardlink exclusion, manually chosen keeper, confirmed selected-copy Trash |
| Parallel scanning | Two bounded workers by default; automatic reductions for heat/power/volume/CPU conditions; deterministic results and cancellable child tasks; optional memory-only repeat-scan fingerprints and clear control |
| File safety | Ownership and ancestor checks, symlink/package/credential/source/database protection, revalidation, descriptor-pinned staging and rollback |
| Cancellation and failure reporting | Scans and action queues cancel; completed actions are reported; partial failures retain per-item explanations |
| Performance results | Comparable CPU sample windows, memory estimate, swap, app count and relevant-volume available capacity; moved bytes are distinguished from space freed |
| Developer versions | Local fixed-argument inspection of Node, npm, pnpm, Yarn, Homebrew, Xcode, Swift and Docker; timeout/cancellation/output limits |
| Docker | Local Unix-socket engine status and aggregate resources only; no container, image or volume mutations |
| Development processes | Own-user standalone Node/Bun/Deno PID, path, CPU and memory; separately confirmed SIGTERM with fresh identity validation and observed outcome |
| Startup | Opens macOS Login Items settings with guidance; no unsupported third-party item enumeration or file edits |
| History | Local aggregate scans, cleanup, Boost, quit and development-process outcomes; counts, estimated moved bytes and observed capacity deltas; clear confirmation |
| Tests | 94 regression tests passed plus a separately enabled Release benchmark; real macOS Trash move/restore smoke checks used synthetic data only |

## Remaining platform and release boundaries

- CPU temperature in Celsius is unavailable through the supported public telemetry used here; the UI states this explicitly.
- Apple's private memory-pressure score is not used; VM availability is labeled as an estimate.
- Specialized DerivedData/package-store/Homebrew/Docker maintenance, arbitrary log/temp removal, port/project discovery and simulator data management are not exposed as cleanup actions.
- The repository is a Swift Package; Developer ID signing, notarization, a native Xcode project and public distribution are not configured.
- Trash is not emptied by MacPulse. Moving data there generally does not immediately free capacity. No speed improvement is guaranteed.
