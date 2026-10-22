#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN=".build/release/FreentoSwitcher"
APP="build/FreentoSwitcher.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/FreentoSwitcher"
cp Resources/Info.plist "$APP/Contents/Info.plist"
echo "APPL????" > "$APP/Contents/PkgInfo"
codesign --force --sign - "$APP"
echo "Built $APP"
