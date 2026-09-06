#!/usr/bin/env bash
# Dev loop: kill any running instance, package, launch.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"

pkill -x "$APP_NAME" 2>/dev/null || true
"$ROOT/Scripts/package_app.sh" release
open "$ROOT/${APP_NAME}.app"
