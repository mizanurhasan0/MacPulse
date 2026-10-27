# Release notes

This Swift Package currently builds a local macOS executable. Before distribution, configure a native `.app` bundle, bundle identifier, version/build number, app icon, Developer ID signing, hardened runtime, and notarization.

The app expects Mole to be installed separately and available as `mo`. A distributable version should document and validate the supported Mole versions and installation paths. Do not describe the app as standalone while it delegates cleanup to an external Mole installation.
