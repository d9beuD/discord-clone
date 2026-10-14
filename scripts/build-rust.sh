#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.cargo/bin:$PATH"
CONFIGURATION="${CONFIGURATION:-Debug}"
PROFILE=debug
CARGO_PROFILE=dev
if [[ "$CONFIGURATION" == Release ]]; then
    PROFILE=release
    CARGO_PROFILE=release
fi
export MACOSX_DEPLOYMENT_TARGET=27.0
GENERATED="$ROOT/apps/macos/Generated/$CONFIGURATION"
mkdir -p "$GENERATED"
cargo build --locked -p apple-bridge --lib --target aarch64-apple-darwin --profile "$CARGO_PROFILE"
cargo run --locked -p apple-bridge --features bindgen --bin uniffi-bindgen -- \
    generate --library "$ROOT/target/aarch64-apple-darwin/$PROFILE/libapple_bridge.dylib" \
    --language swift --config "$ROOT/crates/apple-bridge/uniffi.toml" --out-dir "$GENERATED"
cp "$ROOT/target/aarch64-apple-darwin/$PROFILE/libapple_bridge.a" "$GENERATED/libapple_bridge.a"
