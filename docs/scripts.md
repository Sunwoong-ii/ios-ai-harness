# 프로젝트 스크립트

각 iOS 프로젝트에 설치되는 스크립트(`template/scripts/harness/`)의 동작 방식이다.
에이전트·사람·CI가 같은 스크립트를 쓴다. 모든 스크립트는 `.harness/project.json`을 읽는다([project-config.md](project-config.md)).

## 공통

- **출력**: 성공하면 한 줄, 실패하면 원인을 찾는 데 필요한 만큼만 출력한다. 전체 로그와 결과 번들은 파일로 남기고 경로만 알려준다.
- **산출물 위치**

  | 경로 | 내용 |
  |---|---|
  | `.harness/out/` | 마지막 실행의 로그(`*.log`)와 결과 번들(`*.xcresult`). 실행할 때마다 덮어쓴다. test는 스킴마다 따로 남긴다(`test-<스킴>.log`) |
  | `.harness/out/ui/` | ui가 남기는 화면 요소 원본(`tree.json`)과 스크린샷. run을 실행할 때마다 비운다 |
  | `.harness/state/` | 다음 실행이 참고하는 로컬 상태(생성 입력 지문 등) |
  | `~/Library/Developer/Xcode/DerivedData/<워크트리 이름>-harness-<경로 해시>` | 이 워크트리 전용 DerivedData. `HARNESS_DERIVED_DATA`로 바꿀 수 있다 |

  - `.harness/.gitignore`가 설정 파일만 남기고 나머지를 무시한다.
  - DerivedData를 프로젝트 안에 두지 않는 이유가 있다. 프로젝트가 `~/Desktop` 같은 macOS 보호 폴더 아래 있으면, 시뮬레이터의 테스트 프로세스가 테스트 번들을 읽지 못한다([harness-log.md](harness-log.md) 2026-10-02).
  - 경로 해시를 이름에 넣어서 워크트리끼리 빌드 캐시가 섞이지 않게 한다.
- **프로젝트 생성(Tuist·XcodeGen)**: 빌드 전에 생성이 필요한지 스스로 판단한다.
  - 생성 입력의 지문이 지난번과 다르면 install·generate를 다시 실행한다. 지문은 git이 보는 파일 목록과 manifest 내용으로 만든다.
  - 그래서 파일을 추가·삭제·이동하거나 manifest를 바꾸면 자동으로 다시 생성된다. 소스 내용만 바뀌었을 때는 건너뛴다.
  - 생성된 프로젝트 파일이 없으면 항상 생성한다. `--generate`를 주면 무조건 다시 생성한다.
  - Tuist가 생성 뒤 Xcode를 여는 동작은 `TUIST_GENERATE_OPEN=false`로 끈다.
- **시뮬레이터**: 설정의 기기 이름과 OS로 UDID를 찾는다. 없으면 설치된 iPhone 목록을 보여주고 멈춘다.
- **종료 코드**: 성공 0, 빌드·테스트 실패는 xcodebuild의 코드(보통 65), 화면 조작(run·ui) 실패 1, 설정·인자 오류 2

## build

```bash
scripts/harness/build                    # 앱 스킴 빌드
scripts/harness/build --scheme FeatureA  # 다른 스킴 빌드
scripts/harness/build --generate         # 프로젝트를 다시 생성한 뒤 빌드
```

- 순서: 필요하면 install·generate → `xcodebuild build -quiet` → `xcresulttool get build-results`로 요약
- 성공: `✓ build MotoTrace · iPhone 17 Pro · 4s · 경고 0`
- 실패: 첫 에러부터 최대 5개를 `경로:줄:열: 메시지`로 보여주고, 로그와 결과 번들 경로를 붙인다.
  - 최대 개수는 `HARNESS_MAX_ERRORS`로 바꾼다.
  - 결과 번들에 에러가 없는 실패(인자 오류, 스크립트 단계 실패)는 로그의 에러 줄을 보여준다.

## test

```bash
scripts/harness/test                          # 앱 단위 테스트 (app.unitTestTargets만, UI 테스트 제외)
scripts/harness/test --scheme CoreTracking    # 모듈 스킴의 테스트
scripts/harness/test --only CoreTrackingTests/LeanAngleAnalyzerTests   # 일부만
```

- 순서: 필요하면 install·generate → `xcodebuild test -quiet` → `xcresulttool get test-results`로 요약
- 성공: `✓ test CoreTracking · 통과 20 · 7s`. 테스트가 0개면 `실행된 테스트 없음`으로 표시한다.
- 실패: 실패한 테스트마다 두 줄을 출력하고, 로그와 결과 번들 경로를 붙인다.
  ```
    Modules/Core/CoreTracking/Tests/Sources/LeanAngleAnalyzerTests.swift:70: XCTAssertEqual failed: ("1") is not equal to ("2")
      ↳ LeanAngleAnalyzerTests/test_updateAttitude_첫데이터_영점_캘리브레이션()
  ```
  - 결과 번들에는 파일 이름만 기록된다. git이 아는 파일 중 하나로 특정되면 루트 기준 경로로 바꿔 보여준다.
  - 테스트가 시작되기 전에 멈췄으면(테스트 쪽 빌드 실패 등) 빌드 에러를 build와 같은 형식으로 보여준다.
- 앱에 단위 테스트 타깃이 없으면 실행하지 않고 그 사실만 출력한다.

## verify

```bash
scripts/harness/verify               # 커밋하지 않은 변경을 검증
scripts/harness/verify --base main   # main에서 갈라진 뒤의 모든 변경을 검증 (PR 전)
scripts/harness/verify --all         # 앱과 테스트가 있는 모든 모듈
scripts/harness/verify --plan        # 실행하지 않고 무엇을 할지만 출력
```

- 바뀐 파일(기본: HEAD 대비 수정 + 새 파일)을 모듈별로 묶는다.
  - 파일이 속한 모듈은 `modules.manifest`(Project.swift)가 있는 가장 가까운 상위 디렉터리다.
  - 앱 디렉터리(`app.path`)의 변경은 앱 단위 테스트로 이어진다.
  - `Tuist/`, `Workspace.swift`, 루트 manifest가 바뀌면 영향 범위를 알 수 없어서 전체를 테스트한다.
  - 모듈 구조가 없는 프로젝트(xcodeproj 단일 앱)는 모든 변경을 앱 변경으로 본다.
- 앱을 먼저 빌드하고, 성공하면 바뀐 모듈의 테스트를 실행한다.
  - 앱을 먼저 빌드하는 이유: 모듈끼리의 컴파일 오류는 앱 빌드가 먼저 잡는다. 또 선언하지 않은 의존(implicit import) 때문에 모듈 스킴만으로는 빌드가 깨지는 프로젝트도 있다.
  - 바뀐 모듈에 의존하는 다른 모듈의 테스트는 돌리지 않는다. 이런 테스트 회귀가 실제로 문제가 되면 그때 추가한다.
- 테스트할 대상이 있는지는 생성된 스킴 파일의 테스트 액션으로 판단한다. `Tests` 폴더만 있고 테스트 타깃이 없는 모듈도 있어서다. 스킴 파일이 없으면 `modules.testsDir` 폴더로 판단한다.
- 단계마다 build·test가 한 줄씩 출력하고, 마지막 줄에 전체 결과를 출력한다.
  ```
  ✓ build MotoTrace · iPhone 17 Pro · 21s · 경고 1
  ✓ test CoreTracking · 통과 20 · 7s
  ✓ verify · 통과: CoreTracking · 29s
  ```

## run

```bash
scripts/harness/run                          # 앱을 빌드하고 시뮬레이터에 설치해 실행
scripts/harness/run -- -UseMockSensors       # 앱에 실행 인자 전달
scripts/harness/run --scheme FeatureADemo    # 다른 스킴의 앱(모듈 Demo 앱 등) 실행
```

- 순서: build → 빌드 설정에서 앱 경로 읽기 → 시뮬레이터가 꺼져 있으면 부팅 → 설치 → 실행
  - 항상 build부터 한다. 코드를 고친 뒤 예전 빌드를 띄워 확인하는 실수를 막기 위해서다. 바뀐 게 없으면 빌드는 몇 초면 끝난다.
  - 앱 경로는 결과물 폴더를 뒤지지 않고 `xcodebuild -showBuildSettings`에서 읽는다. Demo 앱처럼 `.app`이 여럿인 프로젝트가 있어서다. 번들 ID는 빌드된 앱의 Info.plist에서 읽는다.
  - 이미 실행 중이면 종료하고 다시 실행한다. 시뮬레이터 창은 열지 않는다. 보고 싶으면 Xcode 27부터는 Device Hub(`Xcode.app/Contents/Applications/DeviceHub.app`), 그 전에는 Simulator 앱을 연다.
  - 창을 여는 일은 run이 하지 않는다. Xcode 27에서 Simulator 앱이 없어져서 `open -a Simulator`가 실패한다.
- 성공: build 줄 다음에 `✓ run MotoTrace · iPhone 17 Pro · 3s · 앱 로그: .harness/out/app.log`
- 앱 로그(`.harness/out/app.log`): 앱의 표준 출력·에러다. `OS_ACTIVITY_DT_MODE`를 켜서 Xcode 콘솔처럼 `Logger`·`os_log` 출력도 함께 남는다.
- 실패: 빌드가 실패하면 build의 출력과 종료 코드로 끝난다. 설치·실행이 실패하면 `run.log`의 끝부분을 보여준다.

## ui

```bash
scripts/harness/ui tree                      # 화면 요소 요약
scripts/harness/ui shot 로그인               # 스크린샷 → .harness/out/ui/<시각>-로그인.jpg
scripts/harness/ui tap --id loginButton      # 접근성 식별자로 누르기
scripts/harness/ui tap --label 로그인         # 접근성 라벨로 누르기
scripts/harness/ui type "북한강 라이딩"       # 누른 입력란에 붙여 넣기
```

- run으로 실행한 시뮬레이터(설정의 `destination`)를 다룬다. 꺼져 있으면 run을 먼저 실행하라고 안내한다.
- tree·tap·type은 AXe가 필요하다(`brew install cameroncooke/axe/axe`, 1.8.0 이상). 없으면 설치 명령을 보여주고 멈춘다. shot은 simctl만 쓴다. 왜 AXe인지는 [ADR 0005](decisions/0005-ui-observation.md)에 있다.
- **tree**: 접근성 트리를 요소마다 한 줄로 줄인다. 원본(`.harness/out/ui/tree.json`)은 화면 하나에 수백 KB라서 그대로 보여주지 않는다.
  ```
  · 화면 요소 9개 · 원본: .harness/out/ui/tree.json
    Button "START RECORDING" #startRecordingButton @24,723 354x52
    RadioButton "History" #clock.arrow… =1 @197,795 94x54
    StaticText "아직 기록된 투어가 없습니다" @111,456 178x19
  ```
  - 형식: `타입 "라벨" #식별자 =값 (비활성) @x,y 너비x높이`. 식별자·값이 라벨과 같으면 생략한다.
  - 빼는 것: 라벨·값이 없는 배치용 컨테이너, 화면 밖(크기 0) 요소, 시스템 스크롤 막대, 라벨이 있는 버튼 안의 텍스트·이미지, 연달아 같은 줄
  - 화면 키보드는 자판마다 요소가 있어서 `Keyboard (화면 키보드가 떠 있음)` 한 줄로 줄인다.
  - 지도(MapKit) 위의 지명·핀은 지역에 따라 수십 개씩 나와서 `지도 표시 38개 (춘천, 양주, 강릉, 고양, 서울, …)` 한 줄로 줄인다.
  - 값이 80자를 넘으면 잘라서 `…`을 붙인다. iOS 27의 지도 이미지는 값에 지도 상태 JSON을 통째로 담는다.
  - 200줄이 넘으면 나머지 개수만 알린다.
- **shot**: 원본 PNG(수 MB)를 `sips`로 긴 변 1200px JPEG로 줄인다(약 100KB). 이름의 공백과 `/`는 `_`로 바꾼다.
- **tap**: 요소가 나타날 때까지 최대 5초 기다리고, 누른 뒤 화면 전환을 위해 0.5초 쉰다. 못 찾으면 AXe 메시지의 첫 문장과 tree 안내를 보여준다.
- **type**: 텍스트를 시뮬레이터 클립보드에 넣고(`simctl pbcopy`) Cmd+V로 붙여 넣는다. 먼저 `tap`으로 입력란을 누른다.
  - 키 입력(`axe type`)을 쓰지 않는 이유: 시뮬레이터 키보드 언어에 따라 다른 글자가 들어간다. 한글 두벌식이면 `Harness`가 `ㅗㅁ굳ㄴㄴ`로 들어갔고, 성공으로 보고됐다. 붙여 넣기는 키보드 언어와 상관없고 한글도 된다.
  - 시뮬레이터 클립보드의 내용이 바뀐다.
  - 입력란에 실제로 들어갔는지는 확인하지 않는다(비밀번호 칸은 값이 가려져서 확인할 수 없다). `ui tree`로 본다.
  - 출력에는 입력 내용 대신 글자 수만 쓴다(테스트 계정 비밀번호 등).
- 좌표로 누르는 명령은 두지 않았다. 기기와 레이아웃에 따라 바뀌어서다. 스와이프·스크롤 같은 동작은 필요한 일이 관찰되면 추가한다.

## 프로젝트 시나리오

로그인이나 가상 주행처럼 여러 단계를 거치는 확인 절차는 프로젝트마다 다르다. 하네스에 넣지 않고 프로젝트 스킬(`.claude/skills/<이름>/SKILL.md`)로 만든다.

- run과 ui 명령을 순서대로 적는다. 화면 이동은 접근성 식별자로 한다.
- 앱 쪽에서 준비할 것
  - 시나리오가 누를 요소에 `accessibilityIdentifier`를 붙인다.
  - 가짜 데이터나 테스트 모드가 필요하면 실행 인자(예: `-UseMockSensors`)로 켜게 만든다. `scripts/harness/run -- -인자`로 넘긴다.
- 각 단계에서 무엇을 확인할지(tree의 값, 스크린샷)와 기대 결과를 함께 적는다.
