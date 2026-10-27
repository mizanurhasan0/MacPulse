# MacPulse Cleaner

MacPulse Cleaner is a native macOS cleanup app. It scans known user-level cache, browser cache, app log, and developer build-cache locations, then removes eligible items and shows each path as it is processed. It has no Mole, Homebrew, shell-script, or other third-party runtime dependency.

## Main screens

- **Cleaner:** one button starts the native scan and cleanup. CPU health and available storage remain visible at the top.
- **Activity History:** local summaries of cleanup runs. File paths are not saved in history.
- **Settings:** appearance and language preferences.

The cleaner operates inside the current user's home directory. It skips active app caches, Apple-managed cache folders, symlinks, files owned by other users, and targets that changed after scanning. Eligible data is deleted directly rather than moved to Trash.

## Build and run

```sh
./Scripts/swift.sh build --product MacPulse
./run.sh
```

The project uses Swift 6, SwiftUI, and macOS 14 or later. The launcher selects the full Xcode toolchain at `/Applications/Xcode.app`; set `MACPULSE_DEVELOPER_DIR` if Xcode is installed elsewhere.
