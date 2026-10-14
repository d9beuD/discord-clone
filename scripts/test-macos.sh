#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project apps/macos/DiscordClone.xcodeproj -scheme DiscordClone \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/macos \
    -only-testing:DiscordCloneTests CODE_SIGN_IDENTITY=- test
printf '\nMACOS TESTS PASSED\n'
