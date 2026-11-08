#!/usr/bin/env bash
# 앱 실행과 화면 확인(run·ui)이 쓰는 공용 함수(lib.sh).
# 시뮬레이터 없이 가짜 입력으로 검사한다. 실제 화면은 시험장에서 확인한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
. "$here/../template/scripts/harness/lib.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --- pick_app_product --------------------------------------------------------
settings='[
  {"target":"CoreKit","buildSettings":{"TARGET_NAME":"CoreKit","PRODUCT_TYPE":"com.apple.product-type.framework","TARGET_BUILD_DIR":"/dd/Products","FULL_PRODUCT_NAME":"CoreKit.framework"}},
  {"target":"Helper","buildSettings":{"TARGET_NAME":"Helper","PRODUCT_TYPE":"com.apple.product-type.application","TARGET_BUILD_DIR":"/dd/Products","FULL_PRODUCT_NAME":"Helper.app"}},
  {"target":"App","buildSettings":{"TARGET_NAME":"App","PRODUCT_TYPE":"com.apple.product-type.application","TARGET_BUILD_DIR":"/dd/Products","FULL_PRODUCT_NAME":"App.app"}}]'
assert_eq "app: 스킴과 이름이 같은 앱 타깃" "/dd/Products/App.app" "$(printf '%s' "$settings" | pick_app_product App)"
assert_eq "app: 같은 이름이 없으면 첫 번째 앱" "/dd/Products/Helper.app" "$(printf '%s' "$settings" | pick_app_product Other)"
assert_eq "app: 앱 타깃이 없으면 빈 값" "" "$(printf '%s' '[{"buildSettings":{"PRODUCT_TYPE":"com.apple.product-type.framework"}}]' | pick_app_product App)"

# --- version_at_least --------------------------------------------------------
check_version() { if version_at_least "$1" "$2"; then echo yes; else echo no; fi; }
assert_eq "version: 같으면 통과" "yes" "$(check_version 1.8.0 1.8.0)"
assert_eq "version: 자릿수가 커도 숫자로 비교" "yes" "$(check_version 1.10.0 1.8.0)"
assert_eq "version: 낮으면 실패" "no" "$(check_version 1.7.1 1.8.0)"

# --- harness_require_axe -----------------------------------------------------
fake_axe() { # 버전
  printf '#!/bin/sh\necho %s\n' "$1" > "$work/axe"
  chmod +x "$work/axe"
}
fake_axe 1.8.0
assert_eq "axe: 최소 버전 이상이면 통과" "$work/axe" "$(HARNESS_AXE="$work/axe" harness_require_axe && echo "$axe")"
fake_axe 1.7.1
if out="$( (HARNESS_AXE="$work/axe" harness_require_axe) 2>&1 )"; then code=0; else code=$?; fi
assert_eq "axe: 낮은 버전은 설정 오류(2)" "2" "$code"
assert_eq "axe: 낮은 버전 안내" "harness: AXe 1.7.1는 지원하지 않습니다. 1.8.0 이상이 필요합니다: brew upgrade cameroncooke/axe/axe" "$out"
if out="$( (HARNESS_AXE="$work/none" harness_require_axe) 2>&1 )"; then code=0; else code=$?; fi
assert_eq "axe: 없으면 설치 명령 안내" "2 harness: AXe가 필요합니다: brew install cameroncooke/axe/axe" "$code ${out%% (*}"

# --- summarize_ui_tree ---------------------------------------------------------
# axe describe-ui 출력과 같은 모양: 최상위 배열, 요소마다 type·frame·children
tree='[{"type":"Application","AXLabel":" ","frame":{"x":0,"y":0,"width":402,"height":874},"children":[
  {"type":"Group","AXUniqueId":"label-view","frame":{"x":0,"y":0,"width":402,"height":874},"children":[
    {"type":"Button","AXLabel":"START RECORDING","AXUniqueId":"startRecordingButton","frame":{"x":20.5,"y":700,"width":362,"height":56}},
    {"type":"Button","AXLabel":"저장","AXUniqueId":"저장","enabled":false,"frame":{"x":300,"y":60,"width":80,"height":44}},
    {"type":"StaticText","AXLabel":"속도","AXValue":"72 km/h","frame":{"x":20,"y":120,"width":120,"height":20}},
    {"type":"Slider","AXUniqueId":"zoom","AXValue":50,"frame":{"x":20,"y":160,"width":200,"height":30}},
    {"type":"TextField","AXUniqueId":"tourNameField","frame":{"x":20,"y":200,"width":300,"height":40}},
    {"type":"Button","AXLabel":"다음 페이지 아이콘","frame":{"x":0,"y":0,"width":0,"height":0}}]}]}]'
summary="$(printf '%s' "$tree" | summarize_ui_tree)"
line() { printf '%s\n' "$summary" | sed -n "${1}p"; }
assert_eq "tree: 라벨 없는 컨테이너·화면 밖 요소는 뺀다" "5" "$(printf '%s\n' "$summary" | wc -l | tr -d ' ')"
assert_eq "tree: 라벨·식별자·위치" 'Button "START RECORDING" #startRecordingButton @20,700 362x56' "$(line 1)"
assert_eq "tree: 식별자가 라벨과 같으면 한 번만, 비활성 표시" 'Button "저장" (비활성) @300,60 80x44' "$(line 2)"
assert_eq "tree: 값" 'StaticText "속도" =72 km/h @20,120 120x20' "$(line 3)"
assert_eq "tree: 숫자 값" 'Slider #zoom =50 @20,160 200x30' "$(line 4)"
assert_eq "tree: 라벨 없이 식별자만 있는 입력란" 'TextField #tourNameField @20,200 300x40' "$(line 5)"

# 화면 키보드·스크롤 막대·버튼 안의 텍스트처럼 겹치거나 시스템이 붙인 요소
tree='[{"type":"Application","AXLabel":"App","frame":{"x":0,"y":0,"width":402,"height":874},"children":[
  {"type":"Button","AXLabel":"현재 위치로","frame":{"x":150,"y":428,"width":97,"height":30},"children":[
    {"type":"Image","AXLabel":"Location Services","frame":{"x":164,"y":437,"width":12,"height":12}},
    {"type":"StaticText","AXLabel":"현재 위치로","frame":{"x":182,"y":436,"width":55,"height":14}}]},
  {"type":"Button","frame":{"x":0,"y":500,"width":402,"height":60},"children":[
    {"type":"StaticText","AXLabel":"북한강 라이딩","frame":{"x":16,"y":510,"width":200,"height":20}}]},
  {"type":"Slider","AXLabel":"Vertical scroll bar, 1 page","AXValue":"0%","frame":{"x":328,"y":276,"width":30,"height":52}},
  {"type":"Button","AXLabel":"Dictate","AXUniqueId":"dictation","frame":{"x":325,"y":805,"width":68,"height":68}},
  {"type":"Button","AXLabel":"Dictate","AXUniqueId":"dictation","frame":{"x":325,"y":805,"width":68,"height":68}},
  {"type":"Group","AXUniqueId":"UIKeyboardLayoutStar Preview","frame":{"x":0,"y":583,"width":402,"height":233},"children":[
    {"type":"Button","AXLabel":"ㅂ","frame":{"x":4,"y":590,"width":39,"height":54}},
    {"type":"Button","AXLabel":"ㅈ","frame":{"x":44,"y":590,"width":39,"height":54}}]}]}]'
assert_eq "tree: 키보드는 한 줄, 스크롤 막대·버튼 안 텍스트·연속 중복은 뺀다" 'Application "App" @0,0 402x874
Button "현재 위치로" @150,428 97x30
StaticText "북한강 라이딩" @16,510 200x20
Button "Dictate" #dictation @325,805 68x68
Keyboard (화면 키보드가 떠 있음) @0,583 402x233' "$(printf '%s' "$tree" | summarize_ui_tree)"

# --- 가짜 프로젝트와 명령 ---------------------------------------------------------
# 스크립트를 임시 scripts/에 복사해서, 옆에 둔 가짜 build를 부르게 한다.
# xcrun·xcodebuild는 PATH 앞의 가짜 명령으로 바꾸고, 호출을 $CALLS에 기록한다.
p="$work/project"
mkdir -p "$p/.harness" "$work/scripts" "$work/bin" "$work/dd/App.app"
jq -n '{ schemaVersion: 1, generator: "tuist", commands: {}, workspace: "App.xcworkspace", project: null,
  app: { scheme: "App" }, destination: { simulator: "iPhone 17 Pro", os: "latest" }, modules: null }' > "$p/.harness/project.json"
cp "$here/../template/scripts/harness/lib.sh" "$here/../template/scripts/harness/run" "$work/scripts/"
cat > "$work/dd/App.app/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.example.App</string></dict></plist>
EOF

cat > "$work/scripts/build" <<'EOF'
#!/bin/bash
echo "build $*" >> "$CALLS"
if [ "${FAKE_BUILD_CODE:-0}" != 0 ]; then echo "✗ build 실패"; exit "$FAKE_BUILD_CODE"; fi
echo "✓ build App"
EOF
cat > "$work/bin/xcodebuild" <<'EOF'
#!/bin/bash
echo "xcodebuild $*" >> "$CALLS"
jq -n --arg dir "$FAKE_DD" '[{target: "App", buildSettings: {TARGET_NAME: "App",
  PRODUCT_TYPE: "com.apple.product-type.application", TARGET_BUILD_DIR: $dir, FULL_PRODUCT_NAME: "App.app"}}]'
EOF
cat > "$work/bin/xcrun" <<'EOF'
#!/bin/bash
echo "xcrun $*" >> "$CALLS"
case "$1 $2" in
  "simctl list")
    jq -n --arg state "${FAKE_STATE:-Booted}" \
      '{devices: {"com.apple.CoreSimulator.SimRuntime.iOS-26-5": [{name: "iPhone 17 Pro", udid: "SIM1", state: $state}]}}' ;;
  "simctl install")
    if [ "${FAKE_INSTALL_CODE:-0}" != 0 ]; then echo "An error was encountered processing the command"; exit 1; fi ;;
  "simctl launch")
    echo "launch-env OS_ACTIVITY_DT_MODE=${SIMCTL_CHILD_OS_ACTIVITY_DT_MODE:-}" >> "$CALLS"
    echo "com.example.App: 123" ;;
esac
EOF
chmod +x "$work/scripts/build" "$work/scripts/run" "$work/bin/xcodebuild" "$work/bin/xcrun"
export CALLS="$work/calls" FAKE_DD="$work/dd"
run_fake() { # 스크립트 인자...
  local script="$1"; shift
  : > "$CALLS"
  HARNESS_ROOT="$p" HARNESS_DERIVED_DATA="$work/derived" PATH="$work/bin:$PATH" "$work/scripts/$script" "$@" 2>&1 \
    | sed -E 's/ [0-9]+s( |$)/ Ns\1/'
}
called() { grep -c -- "$1" "$CALLS" || true; }

# --- run ---------------------------------------------------------------------
mkdir -p "$p/.harness/out/ui" && touch "$p/.harness/out/ui/old.jpg"
out="$(run_fake run -- -UseMockSensors)"
assert_eq "run: 빌드 출력 다음에 한 줄" "✓ build App
✓ run App · iPhone 17 Pro · Ns · 앱 로그: .harness/out/app.log" "$out"
assert_eq "run: 앱 스킴으로 빌드" "1" "$(called 'build --scheme App')"
assert_eq "run: 번들 ID와 실행 인자로 다시 실행" "1" "$(called 'simctl launch --terminate-running-process .* SIM1 com.example.App -UseMockSensors')"
assert_eq "run: Logger 출력도 앱 로그로" "1" "$(called 'launch-env OS_ACTIVITY_DT_MODE=enable')"
assert_eq "run: 켜져 있으면 부팅하지 않는다" "0" "$(called 'simctl bootstatus')"
assert_eq "run: 지난 화면 산출물을 비운다" "0" "$(find "$p/.harness/out/ui" -type f | wc -l | tr -d ' ')"

out="$(FAKE_STATE=Shutdown run_fake run --scheme Demo)"
assert_eq "run: 꺼져 있으면 부팅" "1" "$(called 'simctl bootstatus SIM1 -b')"
assert_eq "run: --scheme을 build에 넘긴다" "1" "$(called 'build --scheme Demo')"

if out="$(FAKE_BUILD_CODE=65 run_fake run)"; then code=0; else code=$?; fi
assert_eq "run: 빌드 실패면 빌드 출력만" "✗ build 실패" "$out"
assert_eq "run: 빌드의 종료 코드를 그대로" "65" "$code"
assert_eq "run: 빌드 실패면 설치하지 않는다" "0" "$(called 'simctl install')"

out="$(FAKE_INSTALL_CODE=1 run_fake run)" || true
assert_eq "run: 설치 실패 요약" "✗ run App 실패 · 설치 · iPhone 17 Pro" "$(printf '%s\n' "$out" | sed -n 2p)"
assert_eq "run: 설치 실패면 실행하지 않는다" "0" "$(called 'simctl launch')"

finish
