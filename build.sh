#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP="$ROOT/dist/WindowPilot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/WindowPilot" "$APP/Contents/MacOS/WindowPilot"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
if [ -n "${WINDOWPILOT_SIGNING_HELPER:-}" ]; then
    python3 "$WINDOWPILOT_SIGNING_HELPER" "$APP"
else
    codesign --force --sign "${WINDOWPILOT_SIGNING_IDENTITY:--}" --timestamp=none "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
