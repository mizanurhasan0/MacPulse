# Architecture

```text
SwiftUI Cleaner / Activity History / Settings
                 ↓
             CleanerModel
              ├─ LiveSystemMetricsProvider → Mach CPU counters + Foundation volume capacity
              ├─ NativeCleanerService.scan → fixed user-level cache/log/build-cache roots
              ├─ NativeCleanerService.clean → identity recheck + Foundation removal
              └─ ActivityStore → aggregate local history in UserDefaults
```

The cleaner uses Foundation directory enumeration, Darwin `lstat` metadata, and AppKit's list of running applications. It does not spawn a process or call an external cleanup tool. Each candidate keeps its observed device, inode, owner, modification time, and allowed home-directory root; the action phase checks them again before removal.

The model owns UI state and the two-second metrics refresh. Scanning and removal run on utility tasks; progress and per-path outcomes return to the main actor. Paths are kept only in memory while the cleanup view is open.
