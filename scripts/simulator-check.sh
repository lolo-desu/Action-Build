#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
ARCH="$(uname -m)"
APP="$ROOT/build/Simulator/ERPStable.app"
mkdir -p "$ROOT/build/Simulator"
cp -R "$ROOT/build/Payload/ERPStable.app" "$APP"
xcrun --sdk iphonesimulator clang -arch "$ARCH" -isysroot "$SDK" \
  -mios-simulator-version-min=15.0 -fobjc-arc -O2 -DERP_TESTING=1 \
  -framework UIKit -framework Foundation -framework WebKit -framework CoreGraphics -framework UserNotifications \
  "$ROOT/ERPStable/main.m" -o "$APP/ERPStable"
cp "$ROOT/scripts/layout-fixture.html" "$APP/layout-fixture.html"
codesign --force --sign - "$APP"
SIM_ID="$(python3 - <<'PY'
import json,subprocess
runtimes=json.loads(subprocess.check_output(['xcrun','simctl','list','runtimes','--json']))['runtimes']
runtime=next(r for r in reversed(runtimes) if r.get('isAvailable') and 'iOS' in r['name'])
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devicetypes','--json']))['devicetypes']
phone=next(d for d in devices if d['name']=='iPhone 17 Pro')
print(subprocess.check_output(['xcrun','simctl','create','vrcrp-web-check',phone['identifier'],runtime['identifier']],text=True).strip())
PY
)"
trap 'xcrun simctl shutdown "$SIM_ID" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$SIM_ID"
xcrun simctl bootstatus "$SIM_ID" -b
xcrun simctl install "$SIM_ID" "$APP"
xcrun simctl launch "$SIM_ID" local.erp.stable --verify-keyboard
sleep 9
DATA_PATH="$(xcrun simctl get_app_container "$SIM_ID" local.erp.stable data)"
cp "$DATA_PATH/Documents/layout-first.json" "$ROOT/build/layout-first.json"
cp "$DATA_PATH/Documents/layout-reopened.json" "$ROOT/build/layout-reopened.json"
python3 - "$ROOT/build" <<'PY'
import json,sys
from pathlib import Path
for phase in ['first','reopened']:
    data=json.loads((Path(sys.argv[1])/f'layout-{phase}.json').read_text())
    print(phase,data)
    assert 'error' not in data,data
    assert data['editing'] and data['keyboardVisible'] and data['keyboardHeight']>100,data
    assert data['accessoryRemoved'],data
    assert abs(data['scale']-1)<0.01,data
    assert data['inputTop']>=0,data
    assert data['inputBottom']<=min(data['nativeHeight'],data['visualHeight'])+1,data
    assert abs(data['chatHeight']-data['nativeHeight'])<1,data
print('PASS: real simulator keyboard first show, reopen, accessory removal and visible composer')
PY
xcrun simctl io "$SIM_ID" screenshot "$ROOT/build/web-keyboard.png"
xcrun simctl launch --terminate-running-process "$SIM_ID" local.erp.stable --preview-login
sleep 12
xcrun simctl io "$SIM_ID" screenshot "$ROOT/build/web-login.png"
