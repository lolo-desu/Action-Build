#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if ! command -v xcodegen >/dev/null; then brew install xcodegen; fi
xcodegen generate --spec project.yml
python3 scripts/fixture-server.py > build/touch-fixture-server.log 2>&1 &
SERVER_PID=$!
SIM_ID="$(xcrun simctl create vrcrp-touch-check com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro)"
trap 'kill "$SERVER_PID" >/dev/null 2>&1 || true; xcrun simctl shutdown "$SIM_ID" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$SIM_ID"
xcrun simctl bootstatus "$SIM_ID" -b
set -o pipefail
xcodebuild test -project ERPStable.xcodeproj -scheme GestureChecks \
  -destination "platform=iOS Simulator,id=$SIM_ID" -parallel-testing-enabled NO \
  -derivedDataPath build/UITestDerived -resultBundlePath build/touch-results.xcresult \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee build/touch-tests.log
echo 'PASS: actual XCTest photo tap/right-swipe, delayed/warm profile entry, slow vertical scrolling, horizontal album and dropped-snapshot recovery'
