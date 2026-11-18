#!/usr/bin/env bash
# Run regression tests with either Xcode or only Apple's Command Line Tools.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sony-for-mac-tests.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$ROOT"
swiftc -parse-as-library -D STANDALONE_TESTS \
  Sources/sony_for_mac/Protocol/*.swift \
  Sources/sony_for_mac/Bluetooth/*.swift \
  Sources/sony_for_mac/Support/*.swift \
  Sources/sony_for_mac/Controller/*.swift \
  Sources/sony_for_mac/Automation/*.swift \
  Tests/sony_for_macTests/*.swift \
  -framework IOBluetooth -o "$TEST_DIR/ProtocolTests"
"$TEST_DIR/ProtocolTests"
