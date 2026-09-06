#!/usr/bin/env bash
set -euo pipefail

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

source "$ROOT/version.env"

# Validate values before constructing paths or embedding metadata in XML.
[[ "$CONF" == "debug" || "$CONF" == "release" ]] || { echo "Expected debug or release" >&2; exit 1; }
[[ "$APP_NAME" == "XMControl" ]] || { echo "Unexpected app name" >&2; exit 1; }
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9.-]+$ ]] || exit 1
[[ "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || exit 1
[[ "$MACOS_MIN_VERSION" =~ ^[0-9]+\.[0-9]+$ ]] || exit 1

ARCH_LIST=( ${ARCHES:-} )
if [[ ${#ARCH_LIST[@]} -eq 0 ]]; then
  ARCH_LIST=("$(uname -m)")
fi

for ARCH in "${ARCH_LIST[@]}"; do
  [[ "$ARCH" == "arm64" || "$ARCH" == "x86_64" ]] || { echo "Unsupported architecture" >&2; exit 1; }
  swift build -c "$CONF" --arch "$ARCH"
done

STAGING=$(mktemp -d "$ROOT/.package.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/${APP_NAME}.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>${MACOS_MIN_VERSION}</string>
    <key>LSUIElement</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
        <string>XMControl talks to your Sony headphones over Bluetooth to control noise cancelling, the equalizer, and other playback settings.</string>
    <key>BuildTimestamp</key><string>${BUILD_TIMESTAMP}</string>
    <key>GitCommit</key><string>${GIT_COMMIT}</string>
</dict>
</plist>
PLIST

build_product_path() {
  local name="$1"
  local arch="$2"
  case "$arch" in
    arm64|x86_64) echo ".build/${arch}-apple-macosx/$CONF/$name" ;;
    *) echo ".build/$CONF/$name" ;;
  esac
}

install_binary() {
  local name="$1"
  local dest="$2"
  local binaries=()
  for arch in "${ARCH_LIST[@]}"; do
    binaries+=("$(build_product_path "$name" "$arch")")
  done
  if [[ ${#ARCH_LIST[@]} -gt 1 ]]; then
    lipo -create "${binaries[@]}" -output "$dest"
  else
    cp "${binaries[0]}" "$dest"
  fi
  chmod +x "$dest"
}

install_binary "$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# Ensure contents are writable before stripping attributes and signing.
chmod -R u+w "$APP"

# Remove Finder metadata that interferes with code sealing, preserving quarantine.
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP" 2>/dev/null || true
find "$APP" -name '._*' -delete

# Local development signature with hardened runtime; no permissive entitlements.
codesign --force --sign - --options runtime "$APP"
codesign --verify --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"

# Replace the previous build only after the new bundle has passed verification.
rm -rf "$ROOT/${APP_NAME}.app"
mv "$APP" "$ROOT/${APP_NAME}.app"

echo "Created $ROOT/${APP_NAME}.app"
