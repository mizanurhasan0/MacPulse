# Feature scope

| Area | Behavior |
| --- | --- |
| Cleanup | Native scan and removal of eligible user cache folders, browser cache, old app logs, package-manager caches, and Xcode DerivedData. |
| File visibility | Shows scanned paths, category, allocated-size estimate, and live removed/skipped state. |
| Safety | Limits targets to known locations in the current user's home directory; skips active apps, Apple-managed caches, symlinks, foreign-owned items, and changed targets. |
| System status | Compact CPU utilization and available storage at the top of the Cleaner page. |
| Activity History | Stores run date, status, removed-item count, and observed available-storage delta locally. Paths are not saved. |
| Settings | Appearance, accent color, language, and app information. |

Cleanup logic is implemented in Swift using Foundation, Darwin file metadata, and AppKit's running-application list. The app does not invoke Mole, Homebrew, package-manager cleanup commands, or shell scripts. It handles current-user data and does not request administrator access.
