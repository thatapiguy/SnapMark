#!/bin/bash
# Compiles the demo script together with SnapMarkCore and renders docs/images/editor-example.png.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
# Core sources are compiled in directly, so the module import is dropped.
grep -v "^import SnapMarkCore" scripts/make_demo_screenshot.swift > "$TMP/main.swift"
swiftc -O Sources/SnapMarkCore/*.swift "$TMP/main.swift" -o "$TMP/demo"
"$TMP/demo"
rm -rf "$TMP"
