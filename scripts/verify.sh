#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-rust.sh
./scripts/build-macos.sh --clean
./scripts/test-macos.sh
./scripts/test-ui.sh
