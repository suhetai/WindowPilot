#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
LOCAL_IDENTITY="WindowPilot Local Signing"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP="$ROOT/dist/WindowPilot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/WindowPilot" "$APP/Contents/MacOS/WindowPilot"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
# Prefer an explicit identity, then the local identity from scripts/create-local-signing-identity.sh,
# and fall back to ad-hoc. A stable identity keeps macOS privacy permissions across rebuilds.
IDENTITY="${WINDOWPILOT_SIGNING_IDENTITY:-}"
if [ -z "$IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q "\"$LOCAL_IDENTITY\""; then
    IDENTITY="$LOCAL_IDENTITY"
fi
if [ -n "${WINDOWPILOT_SIGNING_HELPER:-}" ]; then
    python3 "$WINDOWPILOT_SIGNING_HELPER" "$APP"
else
    codesign --force --sign "${IDENTITY:--}" --timestamp=none "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "Signed with: ${IDENTITY:-ad-hoc (permissions reset on every rebuild)}"
echo "Built: $APP"
