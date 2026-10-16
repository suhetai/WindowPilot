#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/windowpilot-checks.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc "$ROOT/Sources/WindowPilot/WindowLogic.swift" "$ROOT/Tests/WindowLogicChecks.swift" -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks"
