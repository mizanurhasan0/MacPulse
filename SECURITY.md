# Security and data handling

MacPulse's cleanup engine is implemented in Swift. It does not launch third-party cleaners, shells, package-manager commands, or privileged helpers.

The scanner considers a fixed set of user-level cache, browser cache, app log, and developer build-cache locations. It reads metadata only. It does not scan the whole disk or inspect file contents. Active-app caches, Apple-managed cache folders, symbolic links, files owned by other users, and paths outside the scanned roots are excluded.

Before removing a target, the app rechecks that the path stays under the current user's home directory, each ancestor is a real user-owned directory, and the target still has the same device and inode observed during scanning. Changed or otherwise ineligible targets are skipped. Eligible targets are removed directly and are not moved to Trash.

Activity History stores only run status, item count, timestamp, and available-storage delta in local UserDefaults. It does not save file paths or file contents. The current scan list stays in memory for the cleanup view.

No account, analytics SDK, cloud backend, external cleaner, or administrator access is required.
