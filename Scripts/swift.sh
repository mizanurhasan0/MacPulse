#!/bin/bash
set -euo pipefail

# Keep the compiler, SDK and SwiftUI macro plugins from the same Xcode install.
# This works even when xcode-select still points to Command Line Tools.
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${MACPULSE_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
    printf '%s\n' "MacPulse needs a full Xcode installation for SwiftUI macro plugins." >&2
    printf '%s\n' "Set MACPULSE_DEVELOPER_DIR to Xcode.app/Contents/Developer if Xcode is installed elsewhere." >&2
    exit 1
fi

# A caller's CLT SDK or custom toolchain must not override the matched Xcode pair.
unset SDKROOT TOOLCHAINS SWIFT_EXEC SWIFT_EXEC_MANIFEST
cd -- "$project_dir"
exec /usr/bin/xcrun --toolchain XcodeDefault swift "$@"
