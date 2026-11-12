#!/usr/bin/env bash
# build·test가 xcodebuild를 어디서, 어떤 인자로 부르는지 가짜 xcodebuild로 검사한다.
# 실제 빌드·테스트는 시험장에서 확인한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# 가짜 xcodebuild는 실행한 폴더와 인자를 $CALLS에 남긴다. xcrun은 시뮬레이터 목록만 돌려준다.
mkdir -p "$work/bin"
cat > "$work/bin/xcodebuild" <<'EOF'
#!/bin/bash
echo "cwd=$PWD $*" >> "$CALLS"
if [ -n "${FAKE_MACRO_ERROR:-}" ] && ! printf '%s\n' "$@" | grep -qx -- -skipMacroValidation; then
  echo '/dd/SourcePackages/checkouts/swift-dependencies/Package.swift:PACKAGE-TARGET:DependenciesMacrosPlugin: error: Macro "DependenciesMacrosPlugin" from package "swift-dependencies" must be enabled before it can be used'
  exit 65
fi
EOF
cat > "$work/bin/xcrun" <<'EOF'
#!/bin/bash
case "$1 $2" in
  "simctl list") jq -n '{devices: {"com.apple.CoreSimulator.SimRuntime.iOS-26-5": [{name: "iPhone 17 Pro", udid: "SIM1", state: "Shutdown"}]}}' ;;
esac
EOF
chmod +x "$work/bin/xcodebuild" "$work/bin/xcrun"

p="$work/project"
mkdir -p "$p/.harness" "$p/Packages"
echo '// manifest' > "$p/Packages/Package.swift"
jq -n '{ schemaVersion: 1, generator: "xcodeproj", commands: { install: null, generate: null },
  workspace: null, project: "App.xcodeproj",
  app: { scheme: "App", path: null, bundleId: null, unitTestTargets: ["AppTests"] },
  destination: { simulator: "iPhone 17 Pro", os: "latest" }, modules: null }' > "$p/.harness/project.json"

export CALLS="$work/calls" HARNESS_ROOT="$p" HARNESS_DERIVED_DATA="$work/dd"
run_script() { # 스크립트 인자...
  : > "$CALLS"
  local name="$1"
  shift
  PATH="$work/bin:$PATH" "$here/../template/scripts/harness/$name" "$@"
}
call() { sed -n 1p "$CALLS"; }
has_arg() { case " $(call) " in *" $1 "*) echo yes ;; *) echo no ;; esac; }

# --- 앱 프로젝트 -----------------------------------------------------------------
run_script test > /dev/null
assert_eq "test: 앱은 루트에서 실행한다" "cwd=$p" "$(call | cut -d' ' -f1)"
assert_eq "test: 앱은 -project를 넘긴다" "yes" "$(has_arg "-project")"

# --- --package: 앱에 연결하지 않은 로컬 패키지 -------------------------------------------
out="$(run_script test --package Packages --scheme Modules-Package)"
assert_eq "package: 패키지 폴더에서 실행한다" "cwd=$p/Packages" "$(call | cut -d' ' -f1)"
assert_eq "package: -project/-workspace를 넘기지 않는다" "no no" "$(has_arg -project) $(has_arg -workspace)"
assert_eq "package: DerivedData는 패키지마다 따로" "yes" "$(has_arg "$work/dd-Packages")"
assert_eq "package: 결과 요약" "✓ test Modules-Package · 실행된 테스트 없음" "${out%% · 0s}"

if out="$(run_script test --package Packages 2>&1)"; then code=0; else code=$?; fi
assert_eq "package: 스킴이 없으면 설정 오류(2)" "2" "$code"
if out="$(run_script test --package Nowhere --scheme X 2>&1)"; then code=0; else code=$?; fi
assert_eq "package: Package.swift가 없으면 설정 오류(2)" "2" "$code"

# --- skipMacroValidation: 매크로 신뢰 확인을 건너뛰는 옵션은 프로젝트가 켤 때만 붙인다 -------------
run_script build > /dev/null
assert_eq "macro: 기본은 붙이지 않는다" "no" "$(has_arg -skipMacroValidation)"

if out="$(FAKE_MACRO_ERROR=1 run_script build)"; then code=0; else code=$?; fi
assert_eq "macro: 매크로 신뢰 확인에 막히면 빌드 실패" "65" "$code"
case "$out" in *'"skipMacroValidation": true를 넣습니다'*) ok=yes ;; *) ok=no ;; esac
assert_eq "macro: 막히면 사용자에게 알리라고 안내한다" "yes" "$ok"

jq '.skipMacroValidation = true' "$p/.harness/project.json" > "$work/c.json" && mv "$work/c.json" "$p/.harness/project.json"
FAKE_MACRO_ERROR=1 run_script build > /dev/null
assert_eq "macro: 켜면 build에 붙인다" "yes" "$(has_arg -skipMacroValidation)"
FAKE_MACRO_ERROR=1 run_script test --package Packages --scheme Modules-Package > /dev/null
assert_eq "macro: 켜면 test --package에도 붙인다" "yes" "$(has_arg -skipMacroValidation)"

finish
