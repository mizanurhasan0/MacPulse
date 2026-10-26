# Release preparation

This repository is not release-ready. Open `Package.swift` in Xcode and create/configure a native macOS app target when Xcode is available, then set the bundle identifier, version/build number, deployment target (macOS 14), app icon, signing identity, and hardened runtime.

For direct distribution, use a Developer ID Application certificate and Apple's notarization workflow. Record the actual signing and notarization output. Never claim notarization without a successful Apple notarization result. The Apple Developer Program, signing certificate, and notarization credentials are external prerequisites.

Before a beta release, complete the missing safety, history, test, and release configuration work in `FEATURES.md`; perform a clean Release build, verify the `.app` behavior on macOS 14 and current macOS, and measure actual archive and installed sizes.
