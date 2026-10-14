#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project apps/macos/DiscordClone.xcodeproj -scheme DiscordClone \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/macos \
    -only-testing:DiscordCloneUITests CODE_SIGN_IDENTITY=- test
printf '\nUI TESTS PASSED\n'
