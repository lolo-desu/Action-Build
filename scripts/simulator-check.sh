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
  -framework UIKit -framework Foundation -framework WebKit -framework CoreGraphics -framework UserNotifications -framework SafariServices -framework ImageIO \
  "$ROOT/ERPStable/main.m" "$ROOT/ERPStable/ThemeNavigation.m" "$ROOT/ERPStable/ChatNotifications.m" "$ROOT/ERPStable/PageNavigation.m" "$ROOT/ERPStable/ExternalBrowser.m" -o "$APP/ERPStable"
cp "$ROOT/scripts/layout-fixture.html" "$APP/layout-fixture.html"
cp "$ROOT/scripts/navigation-fixture.html" "$APP/navigation-fixture.html"
cp "$ROOT/scripts/surface-fixture.html" "$APP/surface-fixture.html"
python3 - "$APP/Info.plist" <<'PY'
import plistlib,sys
from pathlib import Path
p=Path(sys.argv[1]); info=plistlib.loads(p.read_bytes())
info['NSAppTransportSecurity']={'NSAllowsLocalNetworking':True}
p.write_bytes(plistlib.dumps(info,fmt=plistlib.FMT_BINARY))
PY
codesign --force --sign - "$APP"
python3 "$ROOT/scripts/fixture-server.py" > "$ROOT/build/fixture-server.log" 2>&1 &
FIXTURE_SERVER_PID=$!
for attempt in {1..20}; do
  if curl --fail --silent http://127.0.0.1:18765/health >/dev/null; then break; fi
  sleep 1
done
curl --fail --silent http://127.0.0.1:18765/health >/dev/null
SIM_ID="$(python3 - <<'PY'
import json,subprocess
runtimes=json.loads(subprocess.check_output(['xcrun','simctl','list','runtimes','--json']))['runtimes']
runtime=next(r for r in reversed(runtimes) if r.get('isAvailable') and 'iOS' in r['name'])
devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devicetypes','--json']))['devicetypes']
phone=next(d for d in devices if d['name']=='iPhone 17 Pro')
print(subprocess.check_output(['xcrun','simctl','create','vrcrp-web-check',phone['identifier'],runtime['identifier']],text=True).strip())
PY
)"
trap 'kill "$FIXTURE_SERVER_PID" >/dev/null 2>&1 || true; xcrun simctl shutdown "$SIM_ID" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$SIM_ID"
xcrun simctl bootstatus "$SIM_ID" -b
xcrun simctl install "$SIM_ID" "$APP"
xcrun simctl launch "$SIM_ID" local.erp.stable --verify-keyboard
DATA_PATH="$(xcrun simctl get_app_container "$SIM_ID" local.erp.stable data)"
wait_for_report() {
  local report="$1"
  for attempt in {1..90}; do
    if test -f "$DATA_PATH/Documents/$report"; then
      if python3 - "$DATA_PATH/Documents/$report" <<'PYERROR'
import json,sys
data=json.load(open(sys.argv[1]))
if 'error' in data:
 print(data['error'])
 sys.exit(0)
sys.exit(1)
PYERROR
      then
        cp "$DATA_PATH/Documents/$report" "$ROOT/build/$report"
        xcrun simctl io "$SIM_ID" screenshot "$ROOT/build/simulator-timeout.png" || true
        xcrun simctl spawn "$SIM_ID" log show --last 2m --style compact --predicate 'process == "ERPStable"' > "$ROOT/build/simulator-timeout.log" || true
        return 1
      fi
      return 0
    fi
    sleep 2
  done
  xcrun simctl io "$SIM_ID" screenshot "$ROOT/build/simulator-timeout.png" || true
  xcrun simctl spawn "$SIM_ID" log show --last 3m --style compact --predicate 'process == "ERPStable"' > "$ROOT/build/simulator-timeout.log" || true
  echo "Timed out waiting for simulator report: $report" >&2
  return 1
}
wait_for_report layout-reopened.json
cp "$DATA_PATH/Documents/notification-content.json" "$ROOT/build/notification-content.json"
cp "$DATA_PATH/Documents/layout-first.json" "$ROOT/build/layout-first.json"
cp "$DATA_PATH/Documents/layout-reopened.json" "$ROOT/build/layout-reopened.json"
xcrun simctl io "$SIM_ID" screenshot "$ROOT/build/web-keyboard.png"
python3 - "$ROOT/build" <<'PY'
import json,sys
from pathlib import Path
for phase in ['first','reopened']:
    data=json.loads((Path(sys.argv[1])/f'layout-{phase}.json').read_text())
    print(phase,data)
    assert 'error' not in data,data
    assert data['editing'] and data['keyboardVisible'] and data['keyboardHeight']>100,data
    assert data['accessoryRemoved'],data
    assert not data['nativeNavVisible'] and data['nativeTabCount']==5 and data['plainNavigation'],data
    assert abs(data['scale']-1)<0.01,data
    assert data['inputTop']>=0,data
    assert data['inputBottom']<=min(data['nativeHeight'],data['visualHeight'])+1,data
    assert abs(data['chatHeight']-data['nativeHeight'])<1,data
    assert data['messageGap']<2 and data['lastMessageBottom']<=data['messagePaneBottom']+1,data
content=json.loads((Path(sys.argv[1])/'notification-content.json').read_text())
assert content['title']=='测试联系人' and content['subtitle']=='ID: peer-test-id' and content['body']=='测试消息内容',content
assert content['attachmentCount']==1 and content['avatarWidth']==144 and content['avatarHeight']==144,content
assert content['path']=='/matches/thread' and content['thread']=='thread' and content['sound'],content
print('PASS: real simulator notification sender/ID/content/avatar attachment, keyboard first show/reopen, visible latest message and composer')
PY
xcrun simctl launch --terminate-running-process "$SIM_ID" local.erp.stable --verify-tabs
wait_for_report tabs-restored.json
cp "$DATA_PATH/Documents/tabs-immediate.json" "$ROOT/build/tabs-immediate.json"
for phase in tabs modal restored; do cp "$DATA_PATH/Documents/tabs-$phase.json" "$ROOT/build/tabs-$phase.json"; done
python3 - "$ROOT/build" <<'PY'
import json,sys
from pathlib import Path
stages={s:json.loads((Path(sys.argv[1])/f'tabs-{s}.json').read_text()) for s in ['tabs','modal','restored']}
immediate=json.loads((Path(sys.argv[1])/'tabs-immediate.json').read_text())
assert immediate['selectedImmediately']==[3],'selection waited for the web bridge'
for phase in ['onPress','afterIntermediateWebColor']:
    colors=immediate[phase]
    assert colors['selected']==3 and colors['foreground']==colors['expected'] and colors['background']==colors['expected'] and abs(colors['backgroundAlpha']-.1)<.001,colors
for stage,data in stages.items():
    print(stage,data)
    assert 'error' not in data and data['plainNavigation'] and data['nativeTabCount']==5,data
    assert data['path']=='/posts' and data['originalClicks']==1 and data['webNavOpacity']=='0',data
    assert data['nativeTitles']==['探索','喜欢','配对','广场','我的'],data
    for native,web in zip(data['nativeCenters'],data['webCenters']):
        assert max(abs(a-b) for a,b in zip(native,web))<1,data
assert stages['tabs']['nativeNavVisible'] and not stages['modal']['nativeNavVisible'] and stages['restored']['nativeNavVisible'],stages
print('PASS: theme navigation, original tab actions/positions/labels and native navigation avoids website modals')
PY
xcrun simctl io "$SIM_ID" screenshot "$ROOT/build/app-tabs.png"
xcrun simctl launch --terminate-running-process "$SIM_ID" local.erp.stable --verify-ux
wait_for_report ux-dark.json
for phase in discover chat profile chat-return restored dark; do cp "$DATA_PATH/Documents/ux-$phase.json" "$ROOT/build/ux-$phase.json"; done
python3 - "$ROOT/build" <<'PYUX'
import json,sys
from pathlib import Path
stages={s:json.loads((Path(sys.argv[1])/f'ux-{s}.json').read_text()) for s in ['discover','chat','profile','chat-return','restored','dark']}
for stage,data in stages.items():
    print(stage,data)
    assert 'error' not in data and data['plainNavigation'] and not data['overlay'],data
    if stage in ['discover','restored','dark']:
        assert data['nativeNavVisible'] and not data['edgeBackEnabled'],data
        assert len(data['actions'])==3 and all(b['width']>=56 and b['height']>=56 and b['bottom']<=data['navTop']-10 for b in data['actions']),data
    else:
        assert not data['nativeNavVisible'] and data['webNavVisibility']=='hidden' and data['canGoBack'],data
        if stage=='chat':assert data['keyboardVisible'] and data['inputBottom']<=data['nativeHeight'] and not data['edgeBackEnabled'],data
        else:assert data['edgeBackEnabled'],data
    expected=[24/255,28/255,35/255,1] if stage=='dark' else [1,1,1,1]
    assert max(abs(a-b) for a,b in zip(data['statusColor'],expected))<1/255,data
assert stages['chat-return']['path']=='/matches/thread' and stages['restored']['path']=='/discover',stages
assert stages['dark']['statusStyle']==1,stages['dark']
print('PASS: actual iOS root/detail navigation, third-level chat push/back, keyboard, card action spacing and light/dark status bar')
PYUX
xcrun simctl io "$SIM_ID" screenshot "$ROOT/build/app-ux.png"
xcrun simctl launch --terminate-running-process "$SIM_ID" local.erp.stable --verify-motion
wait_for_report motion-restored.json
for phase in root push cancel-preview cancelled detail-preview chat-return restored; do cp "$DATA_PATH/Documents/motion-$phase.json" "$ROOT/build/motion-$phase.json"; done
python3 - "$ROOT/build" <<'PYMOTION'
import json,sys
from pathlib import Path
stages={s:json.loads((Path(sys.argv[1])/f'motion-{s}.json').read_text()) for s in ['root','push','cancel-preview','cancelled','detail-preview','chat-return','restored']}
for stage,data in stages.items():
    print(stage,data)
    assert 'error' not in data and data['documentLoads']==1,data
root,push,cancel,done,detail,chat,restored=[stages[s] for s in ['root','push','cancel-preview','cancelled','detail-preview','chat-return','restored']]
assert root['path']=='/matches' and root['nativeNavVisible'],root
assert push['fullWidthBack'] and push['centerBackAllowed'] and push['protectedBackBlocked'],push
assert push['path']=='/matches/thread' and push['canPreviewParent'] and not push['nativeNavVisible'],push
assert cancel['interactive'] and cancel['previewKey']==root['currentKey'] and abs(cancel['progress']-.45)<.001,cancel
assert abs(cancel['webTranslation']-cancel['webWidth']*.45)<1,cancel
assert not done['transitioning'] and done['path']=='/matches/thread' and done['index']==push['index'] and done['draft']=='保留草稿' and done['webAlpha']==1 and done['webTranslation']==0,done
assert detail['interactive'] and detail['path']=='/u/peer' and detail['previewKey']==push['currentKey'] and detail['previewKey']!=root['currentKey'],detail
assert chat['path']=='/matches/thread' and chat['draft']=='保留草稿' and not chat['nativeNavVisible'] and not chat['transitioning'] and chat['webAlpha']==1,chat
assert restored['path']=='/matches' and restored['index']==0 and restored['nativeNavVisible'] and not restored['transitioning'] and restored['webTranslation']==0,restored
print('PASS: UIKit nested page previews, finger tracking, reverse-velocity cancellation, draft retention, committed parent return and no document reload')
PYMOTION
xcrun simctl io "$SIM_ID" screenshot "$ROOT/build/app-motion.png"
xcrun simctl launch --terminate-running-process "$SIM_ID" local.erp.stable --verify-surfaces
wait_for_report surfaces-completed.json
cp "$DATA_PATH/Documents/"surfaces-*.json "$ROOT/build/"
cp "$DATA_PATH/Documents/"surfaces-*.png "$ROOT/build/"
python3 - "$ROOT/build" <<'PYSURFACES'
import json,sys
from pathlib import Path
names=['edit-entry','edit-keyboard','edit-tabs','edit-return','chat','profile','profile-return','pull','refreshed','overlay-preview','overlay-cancelled','overlay-return','external-a','external-b','external-back','external-forward','dark-pull','light-pull','completed']
stages={s:json.loads((Path(sys.argv[1])/f'surfaces-{s}.json').read_text()) for s in names}
for stage,data in stages.items():
 print(stage,data)
 assert 'error' not in data and data['documentLoads']==1,data
entry,tabs=stages['edit-entry'],stages['edit-tabs']
assert entry['backButton'] and entry['edgeBackAllowed'] and tabs['index']==entry['index'] and tabs['historyLength']==entry['historyLength'],stages
assert stages['edit-keyboard']['keyboard'] and stages['edit-keyboard']['backEnabled'],stages['edit-keyboard']
assert stages['edit-return']['path']=='/me' and stages['edit-return']['index']==0,stages['edit-return']
assert stages['chat']['globalHeaderHidden'] and stages['chat']['chatHeaderTop']==0 and stages['chat']['unread']=='7',stages['chat']
assert stages['profile']['edgeBackAllowed'] and stages['profile']['backButton'] and stages['profile-return']['path']=='/matches/thread',stages
pull=stages['pull'];assert pull['hintVisible'] and pull['hintText']=='松开刷新' and pull['hintTop']>=pull['headerHeight'] and not pull['bounce'] and pull['surfaceColor']==[1,1,1,1],pull
assert stages['refreshed']['refreshes']>=1 and not stages['refreshed']['hintVisible'],stages['refreshed']
assert stages['overlay-preview']['interactive'] and stages['overlay-preview']['overlay'] and stages['overlay-preview']['translation']>0,stages['overlay-preview']
assert stages['overlay-cancelled']['overlay'] and not stages['overlay-cancelled']['transitioning'] and stages['overlay-cancelled']['translation']==0,stages['overlay-cancelled']
assert not stages['overlay-return']['overlay'] and stages['overlay-return']['path']=='/discover',stages['overlay-return']
for phase in ['external-a','external-b','external-back','external-forward']:
 external=stages[phase]['external'];assert external['host']=='localhost' and external['close'] and external['statusVisible'] and external['webTop']==external['barBottom'],external
assert not stages['external-a']['external']['back'] and not stages['external-a']['external']['forward'],stages['external-a']
assert stages['external-b']['external']['back'] and stages['external-b']['external']['url'].endswith('/external/b'),stages['external-b']
assert stages['external-back']['external']['forward'] and stages['external-back']['external']['url'].endswith('/external/a'),stages['external-back']
assert stages['external-forward']['external']['url'].endswith('/external/b'),stages['external-forward']
for phase,expected in [('dark-pull',[24/255,28/255,35/255,1]),('light-pull',[1,1,1,1])]:
 data=stages[phase];assert data['hintVisible'] and not data['bounce'] and data['hintTop']>=data['headerHeight'] and max(abs(a-b) for a,b in zip(data['surfaceColor'],expected))<1/255,data
assert 'external' not in stages['completed'] and stages['completed']['path']=='/discover',stages['completed']
print('PASS: real iOS external URL/header/back/forward/close; profile editing keyboard/back and sibling history; peer chat toolbar/badge; refresh surface and position; overlay preview/cancel/return')
PYSURFACES
xcrun simctl launch --terminate-running-process "$SIM_ID" local.erp.stable --preview-login
sleep 12
xcrun simctl io "$SIM_ID" screenshot "$ROOT/build/web-login.png"
