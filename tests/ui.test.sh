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

finish
