# Testing

Use the project wrapper to select the matched full Xcode compiler, SDK and macro plugins:

```sh
./Scripts/swift.sh test
```

The default suite discovers 95 tests: 94 regression tests pass, and one generated-data benchmark is intentionally skipped unless enabled separately. The Release benchmark also passes when explicitly enabled. Coverage includes diagnosis, CPU sampling, history, large/duplicate discovery, cache fingerprints, filesystem protections, Trash staging/rollback, cancellation, process safety, tool inspection, and complete model workflows.

Parallel-scan coverage checks bounded task counts, deterministic serial/parallel results and keepers, dynamic limit reduction, power/thermal/volume policies, cancellation draining all children, serialized monotonic progress, cached repeat scans retaining full byte comparison, same-size mutation with exactly restored mtime, replacement inodes, deletion, mid-verification mutation, cache expiry/capacity/root boundaries, external-volume restrictions, clearing/disabling reuse, and settings persistence/locking during scans.

The updated Settings scene was rendered at widths 680 and 1180 in English, Bangla and Arabic RTL using isolated preferences. Toggle and clear handlers were exercised; rendered Bangla and Arabic layouts were inspected. This does not claim physical click automation.

Workflow integration covers scan → manual selection → preview → approval → execution → report. It also verifies Smart Boost starts unselected, Cancel preserves files, the keeper can be changed, and the Large Files tab cannot remove all known duplicate copies.

Developer process tests launch only fixture-owned runtimes using POSIX process control and bounded waits. They verify real SIGTERM of the matching fixture and rejection of stale, foreign, self and embedded-app identities. No existing application is terminated by these tests.

Separate macOS integration smoke checks moved newly created regular-file and cache-folder fixtures to the actual Trash, immediately restored them, verified contents, and removed only the generated fixtures.

A generated GUI helper app was also launched, identity-checked, gracefully asked to quit through the production service, and observed terminated. No existing user application was targeted.

Native SwiftUI scenes exercised the same command handlers used by Boost and storage buttons, including the actual review/result sheets and live Bangla/Arabic switching. Direct in-process accessibility button-node traversal was unavailable in this desktop runtime; these checks verify rendered scenes and command flows rather than claiming automated physical clicks on every control.

Use a separate temporary directory and isolated UserDefaults suite for every test. Never run cleanup verification against real Documents, Downloads, app caches or development projects.
