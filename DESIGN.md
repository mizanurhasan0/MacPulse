# Interface direction

MacPulse is organized around a single native cleanup action and a clear view of the paths it processes.

- The Cleaner page has one primary button, scan/cleanup progress, a path list with live outcomes, and compact CPU/storage indicators.
- The sidebar contains only Cleaner, Activity History, and Settings.
- Activity History shows aggregate outcomes without retaining paths.
- Settings keeps appearance, accent, and language preferences.

The cleanup implementation uses macOS frameworks directly and has no third-party cleaner dependency.
