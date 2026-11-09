#!/bin/bash
# Cheapest possible Windows proof from a non-Windows host: type-check what does not
# require a Windows C toolchain, and say plainly which part cannot be checked here.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"
TARGET=x86_64-pc-windows-msvc

if ! rustup target list --installed | grep -q "^$TARGET$"; then
    echo "SKIPPED: target $TARGET is not installed (rustup target add $TARGET)."
    exit 0
fi

echo "Checking the C-free crates for $TARGET"
cargo check --locked -p chat-core -p chat-storage --all-targets --target "$TARGET"

printf '\nNOTE: chat-networking and chat-bridge cannot be cargo-checked for %s on this host.\n' "$TARGET"
printf 'reqwest -> rustls -> ring compiles C for the target and needs the Windows SDK\n'
printf '(cargo-xwin or a real Windows build). Run scripts/build-windows.ps1 on Windows.\n'
