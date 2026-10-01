#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if ! command -v xcrun >/dev/null; then
  echo '需要 macOS 和完整 Xcode（包含 iPhoneOS SDK）。' >&2
  exit 1
fi
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
OUT="$ROOT/build"
APP="$OUT/Payload/ERPStable.app"
mkdir -p "$APP"
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$SDK" \
  -miphoneos-version-min=15.0 -fobjc-arc -O2 \
  -framework UIKit -framework Foundation -framework WebKit -framework CoreGraphics \
  -Wl,-no_adhoc_codesign "$ROOT/ERPStable/main.m" -o "$APP/ERPStable"
cp "$ROOT/ERPStable/Info.plist" "$APP/Info.plist"
cp "$ROOT/ERPStable/interaction.js" "$APP/interaction.js"
plutil -convert binary1 "$APP/Info.plist"
rm -f "$OUT/ERPStable-unsigned.ipa"
(cd "$OUT" && /usr/bin/zip -qr ERPStable-unsigned.ipa Payload)
echo "$OUT/ERPStable-unsigned.ipa"
