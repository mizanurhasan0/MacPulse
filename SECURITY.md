# Security notes

MacPulse has no account, analytics SDK, cloud backend or elevated helper. It uses public macOS telemetry and respects filesystem permissions. It does not bypass TCC, SIP or Gatekeeper.

## Filesystem actions

Scans are read only. User cache cleanup is restricted to eligible immediate folders in the user's Library/Caches directory. Other files must come from a folder explicitly chosen through NSOpenPanel. Files and paths are retained in memory only for the current review.

The default-deny policy rejects symbolic links and substituted ancestors, other users' files, system locations, application/data packages, hidden credentials, source/config/database files, immutable/dataless entries, incomplete cache scans and active-app caches. Owner-ambiguous cache names remain reveal-only. Cache scans capture filesystem identity and an inventory metadata fingerprint; actions refuse changes since preview.

Approved actions move data to Trash using Foundation. A private sibling stage and pinned parent descriptor let the service verify the object moved and attempt a no-overwrite rollback on failure. A failed rollback reports the retained stage location. The service never empties Trash or runs unrestricted recursive deletion.

Duplicate copies use streamed hashes and byte comparison. The keeper is revalidated and compared before each move. The common executor and Trash service both reject deleting all selected verified copies. Large-file selection cannot bypass known duplicate-group protection.

Parallel readers use the same no-follow descriptor validation and full filesystem stamps as serial readers. In-memory fingerprints are eligible for reuse only on known internal local volumes and only while device/inode/size/mtime/ctime/owner/mode/flags/allocation still match. A cache hit never bypasses exact comparison or later action validation. Fingerprints are bounded, never written to disk, and can be disabled or cleared in Settings. Expiration prevents reuse after 10 minutes; expired entries are pruned on the next scan. No content or duplicate-result cache is used.

Cancellation stops future actions. Completed moves remain in Trash, and already sent quit requests/signals cannot be withdrawn.

## Process actions

GUI-app quit rechecks PID, bundle identifier, executable path and launch date, then uses a graceful AppKit request. Standalone Node/Bun/Deno stops require a separate confirmation and fresh UID/start-time/path validation before one SIGTERM. System, foreign-user, own, and embedded-app processes are excluded. Existing user apps and development servers are never sent SIGKILL.

Tool checks use known executable paths and fixed argument arrays without a shell. Their environment disables package-manager updates, downloads and analytics. Output and runtime are bounded. Docker inspection explicitly targets a known local Unix socket, never a configured remote context, and does not prune data.

The bounded command runner may forcibly reap only a version-check subprocess that MacPulse itself launched if it ignores timeout/cancellation. This cleanup is separate from user-selected app/server actions.

## Distribution

The current direct-run Swift Package is unsandboxed. Cross-application termination and development process inspection cannot be promised for a sandboxed distribution. Developer ID signing and notarization still need release configuration.

Tests use uniquely created temporary fixtures and test-owned subprocesses. Real macOS Trash smoke checks move and restore only generated fixture data; no existing user data is cleaned.
