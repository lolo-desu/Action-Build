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
  -framework UIKit -framework Foundation -framework WebKit -framework CoreGraphics -framework UserNotifications \
  -Wl,-no_adhoc_codesign "$ROOT/ERPStable/main.m" -o "$APP/ERPStable"
cp "$ROOT/ERPStable/Info.plist" "$APP/Info.plist"
cp "$ROOT/ERPStable/interaction.js" "$APP/interaction.js"
cp "$ROOT/ERPStable/notifications.js" "$APP/notifications.js"
xcrun ibtool --compile "$APP/LaunchScreen.storyboardc" "$ROOT/ERPStable/LaunchScreen.storyboard" \
  --minimum-deployment-target 15.0 --target-device iphone --target-device ipad
for entry in '120 AppIcon60x60@2x.png' '180 AppIcon60x60@3x.png' '152 AppIcon76x76@2x.png' '167 AppIcon83.5x83.5@2x.png'; do
  read -r size name <<< "$entry"
  sips -z "$size" "$size" "$ROOT/ERPStable/site-icon.png" --out "$APP/$name" >/dev/null
done
plutil -convert binary1 "$APP/Info.plist"
rm -f "$OUT/ERPStable-unsigned.ipa"
(cd "$OUT" && /usr/bin/zip -qr ERPStable-unsigned.ipa Payload)
echo "$OUT/ERPStable-unsigned.ipa"
