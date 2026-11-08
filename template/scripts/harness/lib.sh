# 하네스 스크립트 공용 함수. build·test·verify·run·ui가 source한다. (bash 3.2 호환)
#
# harness_init 이후 쓸 수 있는 변수
#   root          프로젝트 루트 (HARNESS_ROOT 또는 현재 디렉터리의 git 루트)
#   config        .harness/project.json 경로
#   state_dir     .harness/state — 스크립트가 남기는 로컬 상태
#   out_dir       .harness/out — 마지막 실행의 로그와 결과 번들
#   derived_data  워크트리마다 따로 쓰는 DerivedData (harness_derived_data_path 참고)

harness_die() {
  echo "harness: $*" >&2
  exit 2
}

harness_init() {
  command -v jq >/dev/null 2>&1 || harness_die "jq가 필요합니다 (macOS에는 /usr/bin/jq로 기본 포함)"
  root="${HARNESS_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  root="$(cd "$root" && pwd)"
  config="$root/.harness/project.json"
  [ -f "$config" ] || harness_die ".harness/project.json이 없습니다. 하네스 저장소의 scripts/detect --write <프로젝트 경로>로 만드세요"
  state_dir="$root/.harness/state"
  out_dir="$root/.harness/out"
  derived_data="$(harness_derived_data_path "$root")"
  max_errors="${HARNESS_MAX_ERRORS:-5}"
  mkdir -p "$state_dir" "$out_dir"
}

# 워크트리($1)의 DerivedData 경로. HARNESS_DERIVED_DATA가 있으면 그 값을 쓴다.
# 프로젝트 안에 두지 않는다. 프로젝트가 ~/Desktop 같은 macOS 보호 폴더 아래 있으면
# 시뮬레이터의 테스트 프로세스가 테스트 번들을 읽지 못한다(docs/harness-log.md 2026-10-02).
# 워크트리 경로의 해시를 이름에 넣어 워크트리끼리 빌드 캐시가 섞이지 않게 한다.
harness_derived_data_path() {
  if [ -n "${HARNESS_DERIVED_DATA:-}" ]; then
    echo "$HARNESS_DERIVED_DATA"
    return 0
  fi
  echo "$HOME/Library/Developer/Xcode/DerivedData/$(basename "$1")-harness-$(printf '%s' "$1" | shasum -a 256 | cut -c1-8)"
}

# 설정 값을 읽는다. 없거나 null이면 빈 문자열.
cfg() {
  jq -r "($1) // empty" "$config"
}

# xcodebuild의 -workspace/-project 인자를 container_args 배열에 담는다.
harness_container_args() {
  local ws pj
  ws="$(cfg .workspace)"
  pj="$(cfg .project)"
  if [ -n "$ws" ]; then
    container_args=(-workspace "$root/$ws")
  elif [ -n "$pj" ]; then
    container_args=(-project "$root/$pj")
  else
    harness_die "설정에 workspace도 project도 없습니다"
  fi
}

# simctl JSON(stdin)에서 이름($1)과 OS($2: latest 또는 버전)에 맞는 기기의 UDID를 찾는다.
# 같은 이름이 여러 런타임에 있으면 가장 최신 OS를 고른다.
pick_simulator() {
  jq -r --arg name "$1" --arg os "$2" '
    [ .devices | to_entries[]
      | select(.key | test("SimRuntime\\.iOS-[0-9]+-[0-9]+"))
      | (.key | capture("iOS-(?<a>[0-9]+)-(?<b>[0-9]+)") | "\(.a).\(.b)") as $ver
      | .value[] | select(.name == $name) | { udid, ver: $ver } ]
    | map(select($os == "latest" or .ver == $os or (.ver | startswith($os + "."))))
    | sort_by(.ver | split(".") | map(tonumber)) | last | .udid // empty'
}

# 설정의 시뮬레이터로 -destination 값을 만든다. 없으면 사용 가능한 이름을 보여주고 멈춘다.
# destination(-destination 값), destination_label(기기 이름), simulator_udid를 채운다.
harness_destination() {
  local name os json udid
  name="$(cfg .destination.simulator)"
  os="$(cfg .destination.os)"
  os="${os:-latest}"
  [ -n "$name" ] || harness_die "설정에 destination.simulator가 없습니다"
  json="$(xcrun simctl list devices available -j 2>/dev/null)" || harness_die "xcrun simctl을 실행하지 못했습니다"
  udid="$(printf '%s' "$json" | pick_simulator "$name" "$os")"
  if [ -z "$udid" ]; then
    {
      echo "harness: 시뮬레이터 '$name' (iOS $os)를 찾지 못했습니다. 설치된 iPhone:"
      printf '%s' "$json" | jq -r '[ .devices[][] | select(.name | startswith("iPhone")) | .name ] | unique | .[] | "  " + .'
      echo "  .harness/project.json의 destination.simulator를 고치세요"
    } >&2
    exit 2
  fi
  destination="id=$udid"
  destination_label="$name"
  simulator_udid="$udid"
}

# --- 프로젝트 생성 (Tuist·XcodeGen) ---------------------------------------------
# 파일 추가·삭제·이동이나 manifest 변경을 놓치면 새 파일이 빌드에서 빠진다.
# 그래서 생성 입력의 지문이 지난번 생성 때와 다를 때만 다시 생성한다.

# 생성 입력의 지문: git이 보는 파일 목록 + manifest 내용
generate_fingerprint() {
  (
    cd "$root" || exit 0
    # -c는 git 인덱스 기준이라 git rm 없이 지운 파일도 나온다. 작업 트리에 있는 파일만 남긴다.
    files="$(
      git ls-files -co --exclude-standard 2>/dev/null \
        | grep -v '^\.harness/' \
        | while IFS= read -r f; do
            if [ -e "$f" ]; then printf '%s\n' "$f"; fi
          done \
        || true
    )"
    {
      printf '%s\n' "$files" | LC_ALL=C sort
      printf '%s\n' "$files" \
        | { grep -E '(^|/)(Project|Workspace|Tuist|Package)\.swift$|^Tuist/|(^|/)project\.yml$|(^|/)Package\.resolved$' || true; } \
        | LC_ALL=C sort \
        | while IFS= read -r f; do
            if [ -f "$f" ]; then shasum -a 256 "$f"; fi
          done
    } | shasum -a 256 | cut -d' ' -f1
  )
}

# 외부 의존성 선언의 지문
deps_fingerprint() {
  (
    cd "$root" || exit 0
    for f in Tuist/Package.swift Tuist/Package.resolved Package.resolved; do
      if [ -f "$f" ]; then shasum -a 256 "$f"; fi
    done | shasum -a 256 | cut -d' ' -f1
  )
}

# 실패한 단계의 로그 끝부분을 보여준다.
harness_report_step_failure() { # 단계 명령 로그
  echo "✗ $1 실패 ($2)"
  tail -n 20 "$3" | sed 's/^/  /'
  echo "  로그: ${3#$root/}"
}

# 생성기 프로젝트면 필요할 때만 install·generate를 실행한다. $1이 force면 항상 실행한다.
# 실행했으면 generated_now=1. 실패하면 요약을 출력하고 1을 반환한다.
harness_ensure_generated() {
  local force="${1:-}" gen install target fp dfp
  generated_now=0
  gen="$(cfg .commands.generate)"
  [ -n "$gen" ] || return 0
  install="$(cfg .commands.install)"
  target="$root/$(cfg '.workspace // .project')"

  if [ -n "$install" ]; then
    dfp="$(deps_fingerprint)"
    if [ "$force" = force ] || [ "$(cat "$state_dir/install.fingerprint" 2>/dev/null || true)" != "$dfp" ]; then
      if ! (cd "$root" && bash -c "$install") > "$out_dir/install.log" 2>&1; then
        harness_report_step_failure install "$install" "$out_dir/install.log"
        return 1
      fi
      printf '%s\n' "$dfp" > "$state_dir/install.fingerprint"
    fi
  fi

  fp="$(generate_fingerprint)"
  if [ "$force" != force ] && [ -e "$target" ] \
    && [ "$(cat "$state_dir/generate.fingerprint" 2>/dev/null || true)" = "$fp" ]; then
    return 0
  fi
  # Tuist는 생성 뒤 Xcode를 여는 것이 기본값이라 끈다.
  if ! (cd "$root" && export TUIST_GENERATE_OPEN=false && bash -c "$gen") > "$out_dir/generate.log" 2>&1; then
    harness_report_step_failure generate "$gen" "$out_dir/generate.log"
    return 1
  fi
  generate_fingerprint > "$state_dir/generate.fingerprint"
  generated_now=1
}

# --- 모듈 --------------------------------------------------------------------

# 모듈(디렉터리 $1, 스킴 $2)에 실행할 테스트가 있으면 성공.
# 생성된 스킴 파일이 있으면 테스트 액션에 테스트 대상이 있는지 본다. Tests 폴더만 있고 테스트 타깃이
# 없는 모듈도 있어서다. 스킴 파일이 없으면 testsDir($3) 폴더가 있는지로 판단한다.
module_has_tests() {
  local f
  for f in "$root/$1"/*.xcodeproj/xcshareddata/xcschemes/"$2".xcscheme; do
    if [ -f "$f" ]; then
      grep -q '<TestableReference' "$f"
      return $?
    fi
  done
  [ -n "${3:-}" ] && [ -d "$root/$1/$3" ]
}

# --- 앱 실행과 화면 (run·ui) ------------------------------------------------------

# showBuildSettings JSON(stdin)에서 스킴($1)이 만드는 앱의 경로를 찾는다.
# 앱 타깃이 여럿이면 이름이 스킴과 같은 것을, 없으면 첫 번째를 고른다.
pick_app_product() {
  jq -r --arg scheme "$1" '
    [ .[].buildSettings | select(.PRODUCT_TYPE == "com.apple.product-type.application") ]
    | (map(select(.TARGET_NAME == $scheme)) + .) | first
    | if . then "\(.TARGET_BUILD_DIR)/\(.FULL_PRODUCT_NAME)" else empty end'
}

# 스킴($1)의 앱 경로를 app_path에 담는다. 빌드 결과물 폴더를 뒤지지 않고 빌드 설정에서 읽는다.
# Demo 앱처럼 .app이 여럿인 프로젝트가 있어서다. harness_container_args·harness_destination 뒤에 부른다.
harness_app_path() {
  local json
  json="$(xcodebuild -showBuildSettings -json "${container_args[@]}" -scheme "$1" \
    -destination "$destination" -derivedDataPath "$derived_data" 2>/dev/null)" \
    || harness_die "스킴 $1의 빌드 설정을 읽지 못했습니다"
  app_path="$(printf '%s' "$json" | pick_app_product "$1")"
  [ -n "$app_path" ] || harness_die "스킴 $1에 앱 타깃이 없습니다"
}

# 시뮬레이터($1)의 상태(Booted, Shutdown 등). 찾지 못하면 빈 문자열.
simulator_state() {
  xcrun simctl list devices -j 2>/dev/null \
    | jq -r --arg udid "$1" '[ .devices[][] | select(.udid == $udid) | .state ][0] // empty'
}

# 시뮬레이터($1)가 꺼져 있으면 부팅하고 끝날 때까지 기다린다. 시뮬레이터 창은 열지 않는다.
harness_boot_simulator() {
  if [ "$(simulator_state "$1")" = Booted ]; then return 0; fi
  xcrun simctl bootstatus "$1" -b > /dev/null 2>&1 || harness_die "시뮬레이터를 부팅하지 못했습니다 ($1)"
}

# 버전 $1이 $2 이상이면 성공한다 (예: 1.10.0 ≥ 1.8.0).
version_at_least() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -t. -k1,1n -k2,2n -k3,3n | head -n 1)" = "$2" ]
}

# AXe 경로를 axe에 담는다(HARNESS_AXE로 바꿀 수 있다). 없거나 버전이 낮으면 설치 방법을 보여주고 멈춘다.
# AXe는 화면 요소 읽기·탭·입력에만 쓴다. 스크린샷과 앱 실행은 simctl로 한다(ADR 0005).
harness_axe_min_version=1.8.0
harness_require_axe() {
  local version
  axe="${HARNESS_AXE:-$(command -v axe 2>/dev/null || true)}"
  if [ -z "$axe" ] || [ ! -x "$axe" ]; then
    harness_die "AXe가 필요합니다: brew install cameroncooke/axe/axe (화면 요소 읽기·탭·입력에 쓴다. 스크린샷은 AXe 없이 된다)"
  fi
  version="$("$axe" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1 || true)"
  if [ -z "$version" ] || ! version_at_least "$version" "$harness_axe_min_version"; then
    harness_die "AXe ${version:-버전 확인 불가}는 지원하지 않습니다. $harness_axe_min_version 이상이 필요합니다: brew upgrade cameroncooke/axe/axe"
  fi
}

# axe describe-ui JSON(stdin)을 요소마다 한 줄로 요약한다: 타입 "라벨" #식별자 =값 (비활성) @x,y 너비x높이
# - 라벨이나 값이 있는 요소, 식별자가 있는 Group 이외의 요소만 남긴다. 나머지는 배치용 컨테이너다.
# - 크기가 0인 요소(화면 밖)는 뺀다. 식별자·값이 라벨과 같으면 한 번만 쓴다.
# - 화면 키보드는 자판마다 요소가 있어서 한 줄로 줄인다. 시스템 스크롤 막대는 뺀다.
# - 라벨이 있는 버튼·링크 안의 텍스트·이미지는 버튼 라벨과 겹쳐서 뺀다. 연달아 같은 줄은 한 번만 쓴다.
summarize_ui_tree() {
  jq -r '
    def text: (. // "") | tostring | gsub("^\\s+|\\s+$"; "");
    def visible: (.frame.width // 0) > 0 and (.frame.height // 0) > 0;
    def frame: " @\(.frame.x | floor),\(.frame.y | floor) \(.frame.width | floor)x\(.frame.height | floor)";
    def summarize($in_control):
      (.AXLabel | text) as $label | (.AXUniqueId | text) as $id | (.AXValue | text) as $value
      | ($in_control or ($label != "" and (.type | IN("Button", "Link", "RadioButton", "Cell")))) as $child_in_control
      | if ($id | startswith("UIKeyboardLayout")) then
          (if visible then "Keyboard (화면 키보드가 떠 있음)" + frame else empty end)
        else
          ( select(visible)
            | select($label != "" or $value != "" or ($id != "" and .type != "Group"))
            | select($label | test("scroll bar|스크롤 막대"; "i") | not)
            | select(($in_control and (.type == "StaticText" or .type == "Image")) | not)
            | .type
              + (if $label != "" then " \"\($label)\"" else "" end)
              + (if $id != "" and $id != $label then " #\($id)" else "" end)
              + (if $value != "" and $value != $label then " =\($value)" else "" end)
              + (if .enabled == false then " (비활성)" else "" end)
              + frame ),
          ( (.children // [])[] | summarize($child_in_control) )
        end;
    (if type == "array" then .[] else . end) | summarize(false)' \
    | awk '$0 != prev { print } { prev = $0 }'
}

# --- 결과 요약 ---------------------------------------------------------------

# 결과 번들($1)의 빌드 결과 JSON. 번들이 없거나 읽지 못하면 빈 문자열.
harness_build_results() {
  if [ -d "$1" ]; then xcrun xcresulttool get build-results --path "$1" --compact 2>/dev/null || true; fi
}

# 결과 번들($1)의 테스트 요약 JSON. 번들이 없거나 테스트가 돌지 않았으면 빈 문자열.
harness_test_summary() {
  if [ -d "$1" ]; then xcrun xcresulttool get test-results summary --path "$1" --compact 2>/dev/null || true; fi
}

# 빌드 결과 JSON($1)에서 개수($2: errorCount|warningCount)를 읽는다. JSON이 없으면 0.
build_count() {
  if [ -z "$1" ]; then echo 0; return 0; fi
  case "$2" in
    errorCount) printf '%s' "$1" | jq '.errorCount // (.errors | length)' ;;
    *) printf '%s' "$1" | jq '.warningCount // (.warnings | length)' ;;
  esac
}

# 빌드 실패 원인을 출력한다. 빌드 결과 JSON($1)에 에러가 있으면 위치와 메시지를,
# 없으면(인자 오류, 스크립트 단계 실패 등) 로그($2)의 에러 줄을 보여준다.
harness_print_build_errors() {
  local json="$1" log="$2" count
  count="$(build_count "$json" errorCount)"
  if [ "$count" -gt 0 ]; then
    printf '%s' "$json" | format_issues "$root" errors "$max_errors"
    if [ "$count" -gt "$max_errors" ]; then echo "  … 에러 $((count - max_errors))개 더 있음"; fi
  else
    { grep -E 'error:|ERROR' "$log" || tail -n 20 "$log"; } | head -n 20 | sed 's/^/  /' || true
  fi
}

# 테스트 요약 JSON(stdin)의 실패를 최대 $1개 "테스트: 메시지"로 출력한다.
# 위치 정보가 없을 때(번들 로드 실패, 크래시 등) 쓰는 대체 출력이다.
format_test_failures() {
  jq -r --argjson max "${1:-5}" '
    (.testFailures // [])[:$max][]
    | "  \(.testIdentifierString // .testName): \(.failureText | split("\n")[0])"'
}

# 테스트 트리 JSON(stdin, xcresulttool get test-results tests)에서 실패한 테스트의
# 실패 메시지를 최대 $1개 "테스트ID<TAB>메시지"로 출력한다. 메시지는 보통 "File.swift:42: ..." 형태다.
failed_test_messages() {
  jq -r --argjson max "${1:-5}" '
    [ .. | objects | select(.nodeType? == "Test Case" and .result? == "Failed")
      | (.nodeIdentifier // .name) as $id
      | ([ .children[]? | select(.nodeType == "Failure Message") | .name ] | if length == 0 then [""] else . end)[]
      | "\($id)\t\(split("\n")[0] // "")" ]
    | .[:$max][]'
}

# git이 아는 파일 중 이름($1)이 같은 파일이 하나뿐이면 루트 기준 경로를, 아니면 이름 그대로 출력한다.
resolve_source_path() {
  local matches
  matches="$(cd "$root" && git ls-files -- "$1" "*/$1" 2>/dev/null || true)"
  if [ -n "$matches" ] && [ "$(printf '%s\n' "$matches" | wc -l | tr -d ' ')" = 1 ]; then
    echo "$matches"
  else
    echo "$1"
  fi
}

# 실패한 테스트를 "경로:줄: 메시지"와 테스트 ID로 출력한다. 위치를 못 찾으면 요약의 실패 문구를 쓴다.
harness_print_test_failures() { # 결과번들 요약JSON
  local tests lines re id msg
  tests="$(xcrun xcresulttool get test-results tests --path "$1" --compact 2>/dev/null || true)"
  lines=""
  if [ -n "$tests" ]; then lines="$(printf '%s' "$tests" | failed_test_messages "$max_errors")"; fi
  if [ -z "$lines" ]; then
    printf '%s' "$2" | format_test_failures "$max_errors"
    return 0
  fi
  re='^([^:]+\.swift):([0-9]+): (.*)$'
  while IFS=$'\t' read -r id msg; do
    if [[ $msg =~ $re ]]; then
      echo "  $(resolve_source_path "${BASH_REMATCH[1]}"):${BASH_REMATCH[2]}: ${BASH_REMATCH[3]}"
    elif [ -n "$msg" ]; then
      echo "  $msg"
    fi
    echo "    ↳ $id"
  done <<EOF
$lines
EOF
}

# 산출물 경로를 루트 기준으로 출력한다.
harness_print_artifacts() { # 로그 결과번들
  echo "  로그: ${1#$root/}"
  if [ -d "$2" ]; then echo "  결과: ${2#$root/}"; fi
}

# xcresult가 기록한 파일 URL의 %XX 인코딩을 푼다 (한글·공백 경로).
decode_file_urls() {
  perl -pe 's{(file://[^"#]*)}{ (my $u = $1) =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge; $u }ge'
}

# build-results JSON(stdin)의 이슈($2: errors|warnings)를 최대 $3개 "경로:줄:열: 메시지"로 출력한다.
# 경로는 루트($1) 기준 상대 경로로 바꾼다. xcresult의 줄·열 번호는 0부터 시작한다.
format_issues() {
  decode_file_urls | jq -r --arg root "$1/" --arg kind "$2" --argjson max "${3:-5}" '
    def num($s; $key): ($s | [scan($key + "=([0-9]+)")[0]] | first);
    (.[$kind] // [])[:$max][]
    | (.sourceURL // "") as $u
    | if $u == "" then
        (if .targetName then "  \(.targetName): \(.message)" else "  \(.message)" end)
      else
        ($u | ltrimstr("file://") | split("#")) as $p
        | ($p[0] | ltrimstr($root)) as $path
        | num($p[1] // ""; "StartingLineNumber") as $line
        | num($p[1] // ""; "StartingColumnNumber") as $col
        | "  \($path)"
          + (if $line then ":\(($line | tonumber) + 1)" else "" end)
          + (if $col then ":\(($col | tonumber) + 1)" else "" end)
          + ": \(.message)"
      end'
}
