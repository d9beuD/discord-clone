#!/bin/bash
# Generate the C# bindings consumed by apps/windows from the shared UniFFI contract.
#
# Bindings are read out of a host-built cdylib, so this runs on macOS, Linux or Windows.
# It does not produce the Windows DLL or build the app: see scripts/build-windows.ps1.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.cargo/bin:$PATH"
GENERATOR="${UNIFFI_BINDGEN_CS:-uniffi-bindgen-cs}"
CONFIGURATION="${CONFIGURATION:-Debug}"
case "$CONFIGURATION" in
    Debug) CARGO_PROFILE=dev; PROFILE_DIR=debug ;;
    Release) CARGO_PROFILE=release; PROFILE_DIR=release ;;
    *) echo "CONFIGURATION must be Debug or Release, got $CONFIGURATION" >&2; exit 1 ;;
esac
OUT="$ROOT/apps/windows/Generated"

if ! command -v "$GENERATOR" >/dev/null 2>&1; then
    echo "Missing generator: $GENERATOR" >&2
    echo "Install it once with:" >&2
    echo "  cargo install --locked uniffi-bindgen-cs --git https://github.com/NordSecurity/uniffi-bindgen-cs --tag v0.12.0+v0.32.0" >&2
    exit 1
fi

HOST="$(rustc -vV | sed -n 's/^host: //p')"
cargo build --locked -p chat-bridge --lib --target "$HOST" --profile "$CARGO_PROFILE"

case "$(uname | tr '[:upper:]' '[:lower:]')" in
    darwin*) LIBNAME="libchat_bridge.dylib" ;;
    linux*)  LIBNAME="libchat_bridge.so" ;;
    msys*|mingw64*|cygwin*) LIBNAME="chat_bridge.dll" ;;
    *) echo "Unknown host platform for $(uname)" >&2; exit 1 ;;
esac
LIB="$ROOT/target/$HOST/$PROFILE_DIR/$LIBNAME"
[[ -f "$LIB" ]] || { echo "Expected library not found: $LIB" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
"$GENERATOR" "$LIB" --library --no-format \
    --config "$ROOT/crates/bridge/uniffi.toml" --out-dir="$OUT"
printf 'Generated %s C# files in apps/windows/Generated from %s\n' \
    "$(find "$OUT" -name '*.cs' | wc -l | tr -d ' ')" "$LIBNAME"
