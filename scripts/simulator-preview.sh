#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
ARCH="$(uname -m)"
APP="$ROOT/build/Simulator/vrcrp.app"
mkdir -p "$ROOT/build/Simulator"
cp -R "$ROOT/build/Payload/vrcrp.app" "$APP"
xcrun --sdk iphonesimulator swiftc -swift-version 5 -parse-as-library -O \
  -target "$ARCH-apple-ios26.0-simulator" -sdk "$SDK" \
  -framework SwiftUI -framework UIKit -framework WebKit -framework UserNotifications \
  -framework AVFoundation -framework PhotosUI "$ROOT"/Sources/*.swift -o "$APP/vrcrp"
codesign --force --sign - "$APP"
SIM_ID="$(python3 - <<'PY'
import json,subprocess
runtimes=json.loads(subprocess.check_output(['xcrun','simctl','list','runtimes','--json']))['runtimes']
runtime=next(r for r in reversed(runtimes) if r.get('isAvailable') and 'iOS' in r['name'])
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devicetypes','--json']))['devicetypes']
phone=next(d for d in devices if d['name']=='iPhone 17 Pro')
print(subprocess.check_output(['xcrun','simctl','create','vrcrp-preview',phone['identifier'],runtime['identifier']],text=True).strip())
PY
)"
trap 'xcrun simctl shutdown "$SIM_ID" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$SIM_ID"
xcrun simctl bootstatus "$SIM_ID" -b
xcrun simctl ui "$SIM_ID" appearance dark
xcrun simctl install "$SIM_ID" "$APP"
xcrun simctl launch "$SIM_ID" local.erp.stable --demo
sleep 4
xcrun simctl io "$SIM_ID" screenshot "$ROOT/build/native-explore.png"
xcrun simctl launch --terminate-running-process "$SIM_ID" local.erp.stable --demo --preview-chat
sleep 4
xcrun simctl io "$SIM_ID" screenshot "$ROOT/build/native-chat.png"
