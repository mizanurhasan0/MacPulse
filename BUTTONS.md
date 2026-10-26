# Button and control audit

All action controls have live handlers; unavailable or unsafe actions are disabled with a reason. Native confirmation Cancel controls intentionally rely on the system dialog's automatic dismissal.

| Screen/control | Result | Verification |
| --- | --- | --- |
| Dashboard: Scan and review | Measures and scans; opens an unselected Smart Boost plan | Workflow integration + native scene |
| Boost selections / Run / Confirm | Builds only selected actions; confirms; executes through ActionExecutor | Executor and workflow tests + native scene |
| Cancel remaining work | Cancels pending scan/actions; retains completed outcomes | Scanner, Trash, executor and workflow cancellation tests |
| Storage: Scan user caches | Fresh identities, metadata fingerprints and allocated estimates | Scanner tests + real cache fixture |
| Storage category cards | Switches App caches / Large files / Duplicates; selection remains visible and accessible | Native previews in EN/BN/AR, compact/wide and fixture result states |
| Cache checkbox / Review / Cancel / Move to Trash | Eligibility, exact path preview, explicit approval and reversible move | Workflow tests + native sheets + actual macOS Trash/restore smoke |
| Choose folder | NSOpenPanel directory choice and security-scoped access; Cancel preserves current choice | Native API integration; scanning validation uses generated directories |
| Size threshold / Scan folder | Saves threshold; runs metadata-only large-file scanning or a separate staged duplicate scan | Discovery + workflow tests |
| Duplicate selection / Keep this copy | Changes keeper without automatically selecting deletions; preserves a verified survivor | Discovery, safety and workflow tests |
| Large-file and duplicate cleanup | Explicit preview and Trash; Large Files cannot bypass known duplicate preservation | Executor + workflow tests |
| Show in Finder / Open Trash | Uses NSWorkspace; missing locations/errors produce feedback | Native API integration and real Trash destination smoke |
| Processes: search / clear | Filters name, bundle ID or PID; clear restores results | Live UI handlers |
| Processes: Quit / Confirm | PID, bundle, path and launch-date validation; graceful request and observed result | Protected identity tests + generated real GUI helper smoke |
| Developer: Check versions / Cancel | Bounded local commands and local Docker socket only | Eight command fixture tests + installed-tool probe |
| Developer: Inspect / Stop / Confirm | User-owned runtime inspection; separately approved identity-checked SIGTERM | Seven real test-owned subprocess safety cases |
| Finding: Open section / Snooze | Native module navigation; one-hour snooze; Settings restores findings | Diagnosis tests and live handlers |
| History: Clear / Confirm | Removes local aggregate records only | ActivityStore tests |
| Settings: monitoring, interval, appearance, color, language | Immediate application and saved preferences; RTL for Arabic | Store wiring and native layout/language scenarios |
| Settings: Faster repeat scans / Clear scan memory | Saved reuse preference; disabling clears fingerprints; Clear removes the in-memory cache with feedback; both disabled while busy | Model integration test, cache tests and native settings render/handler smoke in all three languages |
| Startup: Open System Settings | Opens the native Login Items pane; failure has a visible fallback | Supported native URL integration |
| Toolbar refresh / keyboard shortcuts | Fresh metrics; Command-R; Command-Comma opens Settings | Live sampling and command wiring |

See TESTING.md for the distinction between native scene/handler verification and accessibility click automation. See FEATURES.md for platform and release boundaries.
