#!/usr/bin/env bash
# UI 테스트 실행기.
#
# 왜 스크립트가 필요한가: 시뮬레이터에 위치 권한이 "거부"로 한 번 남으면, 다음 실행부터는
# 권한 알럿 자체가 뜨지 않는다. 테스트는 알럿을 기다렸다가 없으면 그냥 지나가고,
# 앱은 "위치 권한이 필요해요"를 띄운 채 러닝을 시작하지 않는다 → RunFlow 테스트가 계속 깨진다.
# 테스트 안에서는 이 상태를 되돌릴 수 없어서(권한은 시뮬레이터 것) 실행 전에 여기서 풀어 준다.
#
#   scripts/uitest.sh                          # 전체 UI 테스트
#   scripts/uitest.sh "iPhone 17 Pro" -only-testing:RunCanvasUITests/RunFlowUITests
set -euo pipefail

DEVICE_NAME="${1:-iPhone 17 Pro Max}"
BUNDLE_ID="${APP_BUNDLE_ID:-name.dongharyu.RunCanvas}"   # 팀원은 Local.xcconfig 의 값으로 덮어쓰면 된다
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

UDID="$(xcrun simctl list devices available | grep -m1 "${DEVICE_NAME} (" | grep -oE '[0-9A-F-]{36}' || true)"
if [ -z "$UDID" ]; then
  echo "시뮬레이터를 찾지 못했습니다: ${DEVICE_NAME}" >&2
  echo "사용 가능한 기기: " >&2
  xcrun simctl list devices available | grep "iPhone" >&2
  exit 1
fi

echo "기기 ${DEVICE_NAME} (${UDID}) 준비 중 — 위치 권한 허용"
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl privacy "$UDID" grant location "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl privacy "$UDID" grant location-always "$BUNDLE_ID" >/dev/null 2>&1 || true

exec xcodebuild test \
  -project "${ROOT}/RunCanvas.xcodeproj" \
  -scheme RunCanvas \
  -destination "platform=iOS Simulator,id=${UDID}" \
  "${@:2}"
