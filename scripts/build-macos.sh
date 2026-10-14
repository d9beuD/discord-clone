#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ACTION=build
if [[ "${1:-}" == --clean ]]; then
    rm -rf "$ROOT/.build/macos" "$ROOT/apps/macos/Generated"
fi
xcodebuild -project apps/macos/DiscordClone.xcodeproj -scheme DiscordClone \
    -configuration Debug -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath .build/macos CODE_SIGN_IDENTITY=- "$ACTION"
printf '\nMACOS BUILD PASSED\n'
