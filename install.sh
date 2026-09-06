#!/usr/bin/env bash
set -euo pipefail

APP_NAME="XMControl"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
OPEN_APP="${OPEN_APP:-1}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
[[ "$INSTALL_DIR" == /* && "$INSTALL_DIR" != / ]] || { echo "INSTALL_DIR must be an absolute application directory." >&2; exit 1; }
APP_PATH="$INSTALL_DIR/$APP_NAME.app"

if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Install the Xcode Command Line Tools: xcode-select --install" >&2
  exit 1
fi

"$ROOT/Scripts/package_app.sh" release
mkdir -p "$INSTALL_DIR"
STAGING=$(mktemp -d "$INSTALL_DIR/.xmcontrol-install.XXXXXX")
cleanup() {
  # Restore the previous app if replacing it failed.
  if [[ -d "$STAGING/previous.app" && ! -e "$APP_PATH" ]]; then
    mv "$STAGING/previous.app" "$APP_PATH"
  fi
  rm -rf "$STAGING"
}
trap cleanup EXIT

ditto "$ROOT/$APP_NAME.app" "$STAGING/$APP_NAME.app"
codesign --verify --deep --strict "$STAGING/$APP_NAME.app"
pkill -x "$APP_NAME" 2>/dev/null || true
if [[ -e "$APP_PATH" || -L "$APP_PATH" ]]; then
  mv "$APP_PATH" "$STAGING/previous.app"
fi
mv "$STAGING/$APP_NAME.app" "$APP_PATH"

if [[ "$OPEN_APP" == "1" ]]; then
  open "$APP_PATH"
fi
echo "Installed: $APP_PATH"
