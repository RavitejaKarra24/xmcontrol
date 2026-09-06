#!/usr/bin/env bash
# Run regression tests with either Xcode or only Apple's Command Line Tools.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/xmcontrol-tests.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$ROOT"
swiftc -parse-as-library -D STANDALONE_TESTS \
  Sources/XMControl/Protocol/*.swift \
  Sources/XMControl/Bluetooth/*.swift \
  Sources/XMControl/Support/*.swift \
  Sources/XMControl/Controller/*.swift \
  Tests/XMControlTests/*.swift \
  -framework IOBluetooth -o "$TEST_DIR/ProtocolTests"
"$TEST_DIR/ProtocolTests"
