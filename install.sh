#!/bin/bash
# Build, replace /Applications/WindowPilot.app, and relaunch.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
bash "$ROOT/build.sh"
pkill -x WindowPilot 2>/dev/null && sleep 0.5 || true
rm -rf /Applications/WindowPilot.app
cp -R "$ROOT/dist/WindowPilot.app" /Applications/
open /Applications/WindowPilot.app
echo "Installed: /Applications/WindowPilot.app"
