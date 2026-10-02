#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
APP="$ROOT/build/Payload/vrcrp.app"
mkdir -p "$APP"
xcrun --sdk iphoneos swiftc -swift-version 5 -parse-as-library -O \
  -target arm64-apple-ios26.0 -sdk "$SDK" \
  -framework SwiftUI -framework UIKit -framework WebKit -framework UserNotifications \
  -framework AVFoundation -framework PhotosUI \
  -Xlinker -no_adhoc_codesign "$ROOT"/Sources/*.swift -o "$APP/vrcrp"
cp "$ROOT/Resources/Info.plist" "$APP/Info.plist"
xcrun ibtool --compile "$APP/LaunchScreen.storyboardc" "$ROOT/Resources/LaunchScreen.storyboard" \
  --minimum-deployment-target 26.0 --target-device iphone --target-device ipad
for entry in '120 AppIcon60x60@2x.png' '180 AppIcon60x60@3x.png' '152 AppIcon76x76@2x.png' '167 AppIcon83.5x83.5@2x.png'; do
  read -r size name <<< "$entry"
  sips -z "$size" "$size" "$ROOT/Resources/AppIcon.png" --out "$APP/$name" >/dev/null
done
plutil -convert binary1 "$APP/Info.plist"
rm -f "$ROOT/build/vrcrp-native-unsigned.ipa"
(cd "$ROOT/build" && zip -qr vrcrp-native-unsigned.ipa Payload)
