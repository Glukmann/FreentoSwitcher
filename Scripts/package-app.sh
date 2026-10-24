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
mkdir -p "$APP/Contents/Resources"
cp Sources/Engine/Checking/seed-triggers.txt "$APP/Contents/Resources/"
# Подпись: локальный сертификат FreentoSigner (стабильная личность — TCC-права
# переживают пересборки). Если сертификат недоступен (другая машина, CI) —
# ad-hoc как раньше.
if security find-identity -p codesigning 2>/dev/null | grep -q "FreentoSigner"; then
  codesign --force --sign "FreentoSigner" "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "Built $APP"
