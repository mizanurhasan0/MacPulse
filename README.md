# MacPulse

MacPulse is a native macOS performance and storage utility using Swift 6, SwiftUI and Apple frameworks. It targets macOS 14 and later and has no third-party package dependencies.

## What works

- Live CPU, per-app CPU/memory, swap, storage, thermal state and bounded recent CPU/memory trends.
- A complete Smart Boost review: collect measurements, scan caches, choose optional apps/cache folders, confirm, execute, cancel remaining work and inspect real before/after observations.
- User-cache analysis and cleaning with explicit selection/path preview. Eligible items move to Trash; active-app, system-managed, unknown-owner, incomplete and changed caches are protected.
- Large and exact duplicate file discovery in a folder you choose. Set a size threshold, reveal files in Finder, choose a keeper, and move selected reviewed files to Trash after confirmation.
- Confirmed graceful GUI-app quit and separately confirmed stops of your standalone Node/Bun/Deno processes. Identity is checked immediately before action; no force quit is used.
- Local version checks for eight developer tools and local Docker engine resources, with output limits, cancellation and timeouts.
- Prioritized findings, one-hour snooze/restore, aggregate local history, saved monitoring/theme/language settings and native Login Items settings navigation.
- Responsive layouts with a 680 × 500 minimum window, English/Bangla/Arabic RTL, System/Light/Dark appearance and four adaptive accent palettes.

## Use the main workflows

**Smart Boost:** Dashboard → Scan and review → select only apps/data you have reviewed → Run selected actions → confirm → observed results.

**Caches:** Storage → App caches → Scan user caches → select eligible folders → Review selected → Move to Trash. Protected rows explain why selection is unavailable.

**Files:** Storage → Large files or Duplicates → Choose folder → choose threshold → Find large files or Find duplicates. Large-file scans read metadata only and finish independently. Use Find duplicates separately for staged content verification. Select files manually; duplicates always preserve a verified keeper, which you can change. Review paths and approve Trash.

**Developer processes:** Developer Tools → Inspect Node / Bun / Deno → Stop process → confirm. CPU rates need two inspections; 100% represents one CPU core. A server can be legitimate even when it uses significant resources.

## Build and run

Xcode is installed at `/Applications/Xcode.app`. Use the project launcher so the compiler, SDK and SwiftUI macro plugins always come from that same installation, even when `xcode-select` points to Command Line Tools:

```sh
cd "/Users/pylot/Downloads/self/MacPulse"
./run.sh
```

To build or run tests:

```sh
./Scripts/swift.sh build --product MacPulse
./Scripts/swift.sh test
```

Use `./run.sh --configuration release` for an optimized build. The launcher can run from any working directory and does not require changing system settings. If Xcode is installed elsewhere, set `MACPULSE_DEVELOPER_DIR` to its `Contents/Developer` directory.

In VS Code, open this folder, run **Developer: Reload Window**, then press **F5** with **Debug MacPulse** selected. The checked-in settings select the full Xcode toolchain; build/debug tasks use the same launcher. Open a new integrated terminal after reloading to receive the configured `DEVELOPER_DIR` for ordinary Swift commands. Alternatively, open `Package.swift` in Xcode, select the `MacPulse` executable scheme, and run it.

If a separate Terminal still reports `SwiftUIMacros.StateMacro` or `plugin for module 'SwiftUIMacros' not found`, use `./run.sh`. That is a build-time toolchain mismatch: the Command Line Tools installation lacks the platform's SwiftUI macro plugin. No app source workaround or extra package dependency is needed.


## Measurements and safety

File scans are read only until approval. Duplicate checks first sample candidate files, then stream full hashes and verify contents byte by byte. Large-file listings are available before that verification. Nested dependency folders are skipped; a 100,000-file cap is explicitly reported as partial. Links, hardlink aliases, packages, cloud placeholders and inaccessible entries are handled explicitly. Protected source/config/database/credential files are reveal-only. No whole-disk background scan runs.

Content scanning uses up to two parallel workers by default. Worker scheduling reduces under Low Power Mode, heat, limited CPU capacity or external/unknown/nonlocal volumes. Metadata enumeration stays serial. Settings → File scanning controls repeat-scan fingerprint reuse and clearing scan memory. Fingerprints are memory only, bounded to 16,384 entries, and eligible for reuse for 10 minutes on internal local volumes after fresh identity validation. Duplicate candidates always receive a full byte comparison, including repeat scans. See BENCHMARKS.md for measured results and limits.

Every action has an observed outcome. Trash still occupies storage; estimated bytes moved are not claimed as bytes freed. Before/after CPU windows, VM memory estimates, swap, process count and relevant-volume capacity can also change because of unrelated system activity. No speed guarantee or invented health score is shown.

Memory state is estimated from VM page availability, not Apple's private pressure score. CPU temperature in Celsius is unavailable through the supported telemetry used here, and is displayed honestly as unavailable.

## Privacy and limits

No account, cloud backend, analytics SDK or elevated helper is included. Developer commands run on demand with fixed arguments and update/download features disabled; Docker inspection is explicitly restricted to a local Unix socket. History stores aggregate counts and observations, not app names or file paths.

Specialized package-store/DerivedData/Homebrew/Docker maintenance, arbitrary log/temp cleaning, simulator data management and complete third-party startup-item control are not exposed as cleanup actions. See FEATURES.md and SECURITY.md for the supported boundaries.

The project is a Swift Package. A native Xcode project, Developer ID signing, notarization and public distribution remain release work.
