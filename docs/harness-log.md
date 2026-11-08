# 하네스 실패 기록

에이전트가 하네스를 쓰면서 실수하거나 막힌 일을 기록한다. 이 기록은 다음에 무엇을 만들지 정하는 근거다.
기록할 때마다 [principles.md](principles.md)의 "실수 → 고칠 층" 기준표로 분류한다.

## 기록 방법

새 항목은 맨 위에 추가한다. 형식은 다음과 같다.

```markdown
### YYYY-MM-DD — 한 줄 요약
- 프로젝트·작업:
- 무슨 일이 있었나: 에이전트가 한 행동과 그 결과. 가능하면 명령과 메시지를 그대로 적는다.
- 원인: 부족했던 계층 (Context / Execution / Validation / Enforcement / State)
- 조치: 어느 층에 무엇을 추가하거나 고칠지. 고치지 않기로 했으면 "보류"와 이유를 적는다.
- 상태: 미해결 | 반영됨 (커밋 또는 단위 번호) | 보류
```

## 기록

### 2026-11-08 — 없는 스킴으로 test하면 원인이 출력에 없다
- 프로젝트·작업: MotoTrace 시험장, 단위 10 완료 기준 확인. 새 세션(`claude -p`, Opus 5.5)에 "History 탭이 최근 기록부터 나오는지 확인해 줘"를 맡김
- 무슨 일이 있었나
  - 에이전트가 기존 테스트를 돌리려고 `scripts/harness/test --scheme CoreDataStorageTests`를 실행했다. 스킴 이름이 아니라 테스트 타깃 이름이었다.
  - 출력은 `✗ test … 테스트 실행 전 중단 (빌드 에러 1)`과 `xcodebuild encountered an error (65)`뿐이었다.
  - "이 스킴이 없다"는 원인은 로그에만 있어서, 에이전트가 `grep -iE "error|scheme"`로 로그를 뒤진 뒤에야 `--scheme CoreDataStorage`로 다시 돌렸다.
- 원인: Execution — 결과 번들에 에러가 하나라도 있으면 그것만 보여줬다. 그 에러가 원인을 담지 않은 문구일 수 있다는 점을 고려하지 않았다.
- 조치: 결과 번들의 에러가 `xcodebuild encountered an error`뿐이면 로그의 `error:` 줄을 함께 보여준다(build·test 공통). 같은 실행에서 원인 줄이 바로 나오는 것을 확인했다.
- 상태: 반영됨 (feature/unit-10-ui-check)

### 2026-11-08 — 새 세션이 화면을 확인할 때 `ios-ui-check` 스킬을 불러오지 않았다
- 프로젝트·작업: 위와 같은 단위 10 완료 기준 확인
- 무슨 일이 있었나
  - 플러그인과 스킬(`ios-harness:ios-ui-check`)은 로드돼 있었지만 에이전트는 스킬을 부르지 않았다.
  - 대신 AGENTS.md 명령 표의 "앱을 실행해 화면 확인" 줄을 보고 `scripts/harness/run --help`, `ui --help`로 사용법을 익혔다.
  - 그 뒤로는 스킬의 절차와 같게 움직였다: run → tree → 위치 권한 알림을 라벨로 닫음 → History로 이동 → tree로 순서 확인 → shot을 열어 봄 → 본 것과 추정한 것을 나눠 보고. 넣어 둔 정렬 버그를 화면에서 찾았다(140초).
- 원인: 실패는 아니다. AGENTS.md 한 줄과 스크립트 도움말만으로 충분했다.
- 조치: 보류. 스킬 설명을 고치거나 강제하지 않는다. 운영 중에 에이전트가 화면 확인을 건너뛰거나 좌표로 누르는 등 스킬이 막으려던 실수가 보이면, 그때 스킬을 불러오게 할 방법을 정한다. 반대로 끝까지 불리지 않으면 스킬을 지우는 것도 검토한다.
- 상태: 보류

### 2026-11-08 — `ui type`이 다른 글자를 넣고도 성공으로 보고한다
- 프로젝트·작업: MotoTrace 시험장, iOS 27.2 시뮬레이터에서 AXe로 가짜 센서 주행 흐름 확인. 투어 이름 알림에 `scripts/harness/ui type "Harness Ride"`
- 무슨 일이 있었나
  - 출력은 `✓ ui type · 12자`였지만, `ui tree`로 보니 입력란 값이 `ㅗㅁ굳ㄴㄴ 꺙ㄷ`였다.
  - AXe의 `type`은 키보드 키 입력(HID)으로 친다. 시뮬레이터 키보드가 한글 두벌식이라 같은 키가 한글 자모로 바뀌었다.
  - 에이전트가 tree를 다시 보지 않았다면 틀린 값을 넣은 채 다음 단계로 갔을 것이다.
- 원인: Execution — 입력 방식이 시뮬레이터 키보드 언어에 따라 결과가 달라지는데, 그 상태를 확인하지 않았다.
- 조치
  - 시뮬레이터 클립보드에 넣고(`simctl pbcopy`, UTF-8 로캘 지정) Cmd+V로 붙여 넣게 바꿨다. 키보드 언어와 상관없고 한글도 들어간다. 붙여넣기 허용 알림도 뜨지 않았다.
  - 비밀번호 칸은 값이 가려져서 들어갔는지 자동으로 확인하지 않는다. 출력과 스킬에서 tree로 확인하라고 안내한다.
- 상태: 반영됨 (feature/unit-10-ui-check)

### 2026-11-08 — iOS 27.2 시뮬레이터에 AXe가 처음 연결할 때 실패한다
- 프로젝트·작업: MotoTrace 시험장, iOS 27.2 시뮬레이터를 새로 부팅한 직후 `scripts/harness/ui tree`
- 무슨 일이 있었나
  - `Timed out creating the simulator remote automation session`으로 실패했다. 하네스의 1초 뒤 재시도도 같은 이유로 실패했다.
  - AXe를 직접 다시 부르니 두 번째(6초)와 세 번째(1초)는 성공했다. iOS 26.3에서도 첫 호출이 `No translation object returned`로 한 번 실패한 적이 있다.
- 원인: Execution — 시뮬레이터와의 자동화 연결을 처음 만들 때 시간이 걸린다. 재시도 횟수와 간격이 부족했다.
- 조치: 연결 생성 실패일 때만 2초 간격으로 세 번까지 시도한다(tree·tap·type). 요소를 못 찾는 실패는 다시 시도하지 않는다. 시뮬레이터를 끈 상태에서 run → tree가 바로 성공하는 것을 확인했다.
- 상태: 반영됨 (feature/unit-10-ui-check)

### 2026-11-08 — Xcode 27에서 테스트 실패의 위치(`파일:줄`)가 빠진다
- 프로젝트·작업: MotoTrace 시험장, macOS 27.2·Xcode 27.2로 올린 뒤 하네스 점검. CoreTracking 테스트에 일부러 실패를 넣고 `scripts/harness/test --scheme CoreTracking` 실행
- 무슨 일이 있었나
  - 실패 메시지와 테스트 ID는 나왔지만, 메시지 앞의 `LeanAngleAnalyzerTests.swift:87:`이 사라졌다. 에이전트가 고칠 위치를 바로 알 수 없다.
  - Xcode 26까지는 결과 번들의 실패 메시지 문장 앞에 `파일 이름:줄:`이 붙어 있었다. Xcode 27부터는 문장에 위치가 없고 `sourceLocation`(절대 경로, 줄 번호) 필드에 따로 있다.
- 원인: Execution — 결과 번들의 형식이 Xcode 버전마다 바뀔 수 있는데, 한 형식만 읽었다.
- 조치
  - 두 형식을 모두 읽는다. 절대 경로는 루트 기준으로 줄인다.
  - Xcode 27 형식 테스트를 추가했다. MotoTrace에서 같은 실패로 위치가 다시 나오는 것을 확인했다.
  - 빌드 에러 위치, 테스트 빌드 실패, 테스트 요약, 실행된 테스트 없음 판정은 Xcode 27.2에서도 그대로 동작했다(`verify --all`).
- 상태: 반영됨 (feature/unit-10-ui-check)

### 2026-11-08 — 시뮬레이터 부팅이 실패하면 원인이 보이지 않는다
- 프로젝트·작업: MotoTrace 시험장, macOS·Xcode를 올린 뒤 처음 실행한 `scripts/harness/run`
- 무슨 일이 있었나
  - 빌드 뒤 `harness: 시뮬레이터를 부팅하지 못했습니다 (UDID)`만 나왔다. `simctl bootstatus`의 출력을 버리고 있어서 원인을 알 수 없었다.
  - 같은 명령을 직접 다시 실행하니 12초 만에 부팅됐다. 업그레이드 직후 시뮬레이터 서비스가 준비되는 중이었던 것으로 보인다.
- 원인: Execution — 실패를 요약할 때 원인이 담긴 출력을 버렸다. "실패하면 첫 에러부터 구체적으로 보여준다"는 원칙을 어겼다.
- 조치: 부팅 출력을 `run.log`에 남기고, 실패하면 설치·실행 실패처럼 로그 끝부분과 경로를 보여준다.
- 상태: 반영됨 (feature/unit-10-ui-check)

### 2026-11-04 — git에 있는 파일을 `rm`으로 지우면 generate를 건너뛴다
- 프로젝트·작업: MotoTrace 시험장의 `.harness/state/generate.fingerprint`를 설명하다가 코드에서 발견. 임시 git 저장소에서 재현했다.
- 무슨 일이 있었나
  - 생성 입력 지문은 `git ls-files -co`로 만든 파일 목록을 쓴다. `-c`는 작업 트리가 아니라 git 인덱스를 본다.
  - 그래서 커밋된 `B.swift`를 `git rm` 없이 `rm`으로 지우면 목록에 그대로 남고, 지문이 바뀌지 않았다.
  - 그러면 generate를 건너뛰고, 생성된 프로젝트가 지운 파일을 계속 참조해 빌드가 실패한다. 에이전트는 보통 `rm`으로 지운다.
  - 회귀 테스트의 "파일이 삭제되면 다시 실행"은 git에 추가하지 않은 파일만 지워서 이 경우를 놓쳤다.
- 원인: Execution — 파일 목록이 작업 트리가 아니라 인덱스 기준이었다.
- 조치
  - 지문을 만들 때 작업 트리에 실제로 있는 파일만 목록에 넣는다. MotoTrace(파일 170개)에서 지문 계산 시간은 445ms → 458ms로 차이가 거의 없다.
  - "git에 있는 파일을 rm으로 지워도 다시 실행" 테스트를 추가했다.
- 상태: 반영됨 (feature/unit-9-test-log-path)

### 2026-11-04 — verify가 여러 스킴을 테스트하면 앞서 실패한 스킴의 로그가 덮어써진다
- 프로젝트·작업: MotoTrace 시험장, 하네스 설치 뒤 `scripts/harness/verify --all` 실행 (앱 빌드 + 테스트 8묶음, 235초)
- 무슨 일이 있었나
  - FeatureHistory 테스트가 빌드 에러로 멈췄고, 출력은 `로그: .harness/out/test.log`, `결과: .harness/out/test.xcresult`를 가리켰다.
  - verify가 이어서 FeatureSettings·FeatureTour·HistoryDetail을 테스트하면서 같은 경로에 덮어썼다.
  - 실행이 끝난 뒤 `test.log`에는 FeatureHistory 에러(`Cannot find 'HistoryFeatureBuilder' in scope`)가 없고, 마지막 HistoryDetail의 로그만 남았다. 출력이 안내한 로그를 열면 다른 스킴의 결과를 보게 된다.
- 원인: Execution — test의 산출물 경로가 스킴과 상관없이 하나(`test.log`, `test.xcresult`)였다. 단독 실행에서는 문제가 없지만 verify처럼 연달아 부르면 마지막 실행만 남는다.
- 조치: test 산출물 이름에 스킴을 넣는다(`test-<스킴>.log`, `test-<스킴>.xcresult`).
- 상태: 반영됨 (feature/unit-9-test-log-path)

### 2026-11-04 — 테스트 함수가 없는 모듈도 verify가 테스트를 실행한다
- 프로젝트·작업: MotoTrace 시험장, 같은 `verify --all` 실행
- 무슨 일이 있었나
  - FeatureSettings·FeatureTour는 `Tests/Sources`에 빈 `Keep.swift`만 있다. 스킴에는 테스트 대상이 등록돼 있어서 verify가 테스트할 모듈로 판단했다.
  - 두 모듈 모두 `✓ test … · 실행된 테스트 없음`으로 끝났고, 각각 24초·29초가 걸렸다(전체 235초 중 53초).
- 원인: Execution — "스킴에 테스트 대상이 있으면 테스트가 있다"는 판단은 테스트 타깃의 존재까지만 본다. 테스트 함수가 있는지는 보지 않는다.
- 조치: 보류. 결과가 틀리지는 않고(실패로 보고하지 않음) 시간만 든다. 테스트 함수를 세려면 XCTest·Swift Testing 소스를 파싱해야 해서 판단 규칙이 복잡해진다. 기본 실행은 바뀐 모듈만 테스트하므로 `--all`이 아니면 영향이 작다. 대기 시간이 실제로 불편해지면 다시 본다.
- 상태: 보류

### 2026-10-21 — 리뷰어가 "규칙 파일을 먼저 읽으라"는 지시를 따르지 않았다
- 프로젝트·작업: MotoTrace 시험장, 단위 8 `ios-reviewer` 확인 (위반 4종을 넣고 터미널 `claude -p`로 리뷰를 맡김)
- 무슨 일이 있었나
  - 1·2차 실행 모두 위반 4종을 잡았다.
  - 하지만 리뷰어는 `git diff`만 보고 바뀐 파일과 규칙 파일을 열지 않았다. 리뷰어 스스로 "규칙 파일은 열어 보지 않았다"고 밝혔다.
  - 처음에는 `;`로 이은 명령을 써서 같은 diff를 여러 번 다시 실행했다.
  - 새 파일 목록용 `git ls-files -o`는 승인이 필요한 명령이라 실행되지 않았다.
- 원인: Context — 지시가 "검토 전에 규칙을 읽는다"는 문장 하나라 다른 설명 사이에 묻혔다. 이번 위반은 프롬프트의 중점 항목만으로 잡혀서, 지시를 지켰는지가 결과에 드러나지 않았다.
- 조치
  - 리뷰어 지시를 번호 매긴 검토 순서로 바꿨다. 2단계에서 바뀐 파일을 Read로 열면 경로 규칙이 자동으로 따라 들어온다.
  - 명령은 하나씩 실행하게 했고, 새 파일 목록은 `git status --porcelain`으로 보게 했다.
  - 출력 마지막 줄에 "열어 본 파일·규칙"을 적게 해서 지시를 지켰는지 보이게 했다.
  - 3차 실행에서 4개 파일을 모두 열었고, 규칙 항목을 근거로 들었다.
- 상태: 반영됨 (단위 8)

### 2026-10-12 — 에이전트가 `git -C <경로>` 형식을 쓰면 ask 규칙을 피해 간다
- 프로젝트·작업: MotoTrace 시험장, 단위 7 권한 규칙 확인 (터미널 `claude -p` 세션)
- 무슨 일이 있었나
  - 대조 실험으로 `git update-index --refresh`를 시켰더니, 에이전트가 스스로 `git -C <워크트리 경로> update-index --refresh`로 실행했다.
  - 권한 규칙은 명령 문장의 앞부분으로 매칭한다. 그래서 같은 방식으로 `git -C <경로> reset --hard`라고 쓰면 `Bash(git reset --hard *)` 규칙에 걸리지 않는다.
- 원인: Enforcement — Bash 권한 규칙이 `git -C` 형식을 덮지 못했다.
- 조치
  - ask 규칙마다 `git -C * …` 형식을 추가했다.
  - `git -C <경로> reset --hard HEAD`가 확인 요청으로 막히는 것을 확인했다.
  - `sh -c`나 `/usr/bin/git`처럼 다르게 쓴 명령은 여전히 덮지 못한다. 실수를 막는 장치라는 한계를 ADR 0004에 적었다.
- 상태: 반영됨 (단위 7)

### 2026-10-02 — Tests 폴더가 있다고 테스트 타깃이 있는 것은 아니다
- 프로젝트·작업: MotoTrace 시험장, 단위 4 `verify --all` 확인
- 무슨 일이 있었나
  - AppDI·Shared 모듈 테스트가 `Unable to start testing`으로 실패했다.
  - 두 모듈에는 `Tests/Sources` 폴더가 있지만, manifest(`makeSingleModule`)가 테스트 타깃을 만들지 않아서 스킴의 테스트 액션이 비어 있었다.
- 원인: Execution — "Tests 폴더가 있으면 테스트가 있다"는 판단 규칙이 틀렸다.
- 조치
  - 생성된 스킴 파일의 테스트 액션에 테스트 대상이 있는지로 판단하도록 바꿨다.
  - 스킴 파일이 없을 때만 Tests 폴더로 판단한다(verify, detect).
- 상태: 반영됨 (단위 4)

### 2026-10-02 — DerivedData를 ~/Desktop 아래에 두면 테스트 번들을 읽지 못한다
- 프로젝트·작업: MotoTrace 시험장(`~/Desktop/MotoTrace/...`), 단위 4 test 스크립트 개발
- 무슨 일이 있었나
  - 프로젝트 안의 `.harness/DerivedData`를 쓰면 `xcodebuild test`가 `Failed to create a bundle instance representing '…/CoreTrackingTests.xctest'. Check that the bundle exists on disk.`로 실패했다. 번들은 실제로 있었다.
  - 같은 스킴(CoreTracking, 테스트 20개)을 Desktop 밖 DerivedData로 돌리면 20개 모두 통과했다.
- 원인: Execution — 시뮬레이터 쪽 테스트 프로세스가 macOS 보호 폴더(~/Desktop) 아래의 번들을 읽지 못하는 것으로 추정한다. 빌드는 터미널 권한으로 되기 때문에 테스트 단계에서만 드러난다.
- 조치
  - DerivedData 기본 위치를 `~/Library/Developer/Xcode/DerivedData/<워크트리 이름>-harness-<경로 해시>`로 바꿨다.
  - 워크트리마다 분리하는 것은 유지한다. `HARNESS_DERIVED_DATA`로 위치를 바꿀 수 있다.
- 상태: 반영됨 (단위 4)
