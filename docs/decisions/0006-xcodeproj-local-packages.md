# 0006. xcodeproj 앱의 로컬 패키지는 패키지 폴더에서 빌드·테스트하고, 매크로 검증 건너뛰기는 프로젝트가 켠다

- 상태: 채택
- 날짜: 2026-11-12

## 배경

두 번째 시험장 WorkoutRest에 하네스를 적용하면서 Tuist가 아닌 구성에서 막히는 곳이 나왔다.

- WorkoutRest는 Xcode 27로 만든 xcodeproj 앱이다.
  - 앱 프로젝트 안에 `project.pbxproj`가 없고, 새 형식 `project.xcproj`만 있다. 끝 쉼표가 있는 JSON이다.
  - 모듈은 하위 폴더 `Packages/`의 SPM 로컬 패키지로 나눈다. 패키지 이름(`WorkoutRestModules`)은 폴더 이름과 다르다.
  - 패키지는 아직 앱 프로젝트에 연결하지 않았다.
  - TCA·swift-dependencies처럼 매크로를 쓰는 패키지에 의존한다.
- 이 구성에서 하네스가 놓친 것
  - detect가 pbxproj만 읽어서 단위 테스트 타깃과 번들 ID가 비었다.
  - 모듈 탐지는 Tuist(`Project.swift`) 전용이었다.
  - verify는 `app.path`가 비어 있으면, 모듈이 있을 때 루트의 앱 소스 변경을 무시했다.
  - build·test는 항상 `-project`/`-workspace`로 실행해서, 앱에 연결하지 않은 패키지는 테스트할 방법이 없었다.
  - 테스트가 없는 패키지(모듈을 하나씩 늘려 가는 초기 단계)는 verify가 건너뛰었다. 앱에 연결하기 전이라 앱 빌드에도 들어가지 않아, 어디서도 컴파일되지 않았다.
  - 패키지 스킴 이름은 제품·타깃 수에 따라 다르다. 하나면 패키지 이름(`WorkoutRestModules`), 여럿이면 전체를 묶은 `WorkoutRestModules-Package`가 더 생긴다.
  - 매크로 패키지는 Xcode에서 신뢰를 확인받기 전에는 CLI 빌드가 "Macro … must be enabled"로 막혔다. 하네스에서 이를 넘길 방법이 없었다.

## 검토한 방법

| 문제 | 방법 | 판단 |
|---|---|---|
| 패키지 빌드·테스트 | **패키지 폴더에서 `-project`/`-workspace` 없이 `xcodebuild build`·`test`** | 채택. 앱에 연결했든 안 했든 같은 방법으로 돌릴 수 있다. iOS 시뮬레이터에서 돈다 |
| | 앱 프로젝트에 연결한 뒤 앱 프로젝트의 패키지 스킴으로 실행 | 연결하기 전에는 쓸 수 없다 |
| | `swift build`·`swift test` | macOS에서 빌드·실행해서 iOS 전용 API를 쓰는 코드는 돌지 않는다 |
| 테스트 없는 패키지 | **verify가 건너뛰지 않고 패키지 폴더에서 빌드한다** | 채택. Tuist 모듈은 앱 빌드에 들어가니 지금처럼 건너뛴다 |
| 패키지 스킴 이름 | **실행할 때 패키지 폴더의 `xcodebuild -list`로 고른다**: `-Package` 스킴이 있으면 그것, 없고 스킴이 하나뿐이면 그것 | 채택. 패키지가 자라 스킴 이름이 바뀌어도 설정을 고치지 않는다. 패키지마다 고르니 패키지가 여럿이어도 된다 |
| | detect가 패키지 이름을 읽어 `<패키지 이름>-Package`를 적는다 | 처음에 채택했다가 바꿨다. 제품·타깃이 하나인 패키지에는 이 스킴이 없었다 |
| | 두 이름을 차례로 시도한다 | 실패한 xcodebuild 실행이 하나 더 남고, 다른 실패와 구분하기 어렵다 |
| 매크로 신뢰 | **설정 파일 `skipMacroValidation`(기본 끔)을 켜면 build·test가 `-skipMacroValidation`을 붙인다** | 채택 |
| | 항상 붙인다 | 매크로 코드를 믿을지는 사람이 정할 일이다. 기본으로 켜지 않는다 |
| | Xcode에서 Trust & Enable을 누른다 | 하네스를 바꿀 필요는 없다. 다만 패키지를 올릴 때마다 다시 눌러야 하고, CLI 빌드가 이 신뢰를 따르는지 확인하지 못했다 |
| `project.xcproj` 편집 | 훅·deny로 pbxproj처럼 막는다 | 막지 않는다. 사람이 읽을 수 있는 JSON이라 pbxproj처럼 쉽게 깨지지 않고, git으로 되돌릴 수 있다 |
| | **규칙으로 고치기 전에 반드시 사용자에게 묻게 한다** | 채택(사용자 결정) |

## 결정

- detect
  - `project.pbxproj`가 없으면 `project.xcproj`에서 타깃·종류·번들 ID를 읽는다. 둘 다 없으면 경고한다.
  - xcodeproj·XcodeGen 앱의 하위 폴더에 `Package.swift`가 있으면, 그 폴더들을 모듈로 본다. `modules.scheme`은 비워 둔다(`null`).
  - `Package.resolved`에 swift-syntax가 있으면 매크로 패키지를 쓴다고 알린다. `skipMacroValidation`은 켜지 않는다.
- verify
  - `app.path`가 비어 있으면 루트로 본다. 모듈에 속하지 않은 파일은 모두 앱의 변경이다. 덜 테스트하는 것보다 더 테스트하는 쪽이 안전하다.
  - `modules.manifest`가 `Package.swift`인 모듈은 `test --package <모듈 폴더>`로 테스트한다. 테스트가 없으면 `build --package <모듈 폴더>`로 빌드한다.
  - `modules.scheme`이 있으면 `--scheme`으로 넘기고, 비어 있으면 build·test가 고른다.
- build·test `--package 폴더`
  - 그 폴더에서 `-project`/`-workspace` 없이 실행한다.
  - `--scheme`이 없으면 그 폴더의 `xcodebuild -list`에서 고른다. 고르지 못하면 스킴 목록을 보여주고 멈춘다.
  - DerivedData는 패키지마다 따로 쓴다. 앱 프로젝트와 패키지는 서로 다른 워크스페이스라 같은 빌드 폴더를 번갈아 쓰지 않게 한다.
  - build는 로그를 스킴마다 남긴다(`build-<스킴>.log`). verify가 패키지 여러 개를 연달아 빌드해도 앞서 실패한 로그가 남는다.
- `skipMacroValidation`
  - `true`면 build·test가 `-skipMacroValidation`을 붙인다.
  - 빌드 로그에 "must be enabled before it can be used"가 있고 설정이 꺼져 있으면, 사용자에게 알리라고 안내한다.
- `project.xcproj`
  - `project-settings.md` 규칙의 대상에 넣고, 고치기 전에 무엇을 왜 바꾸는지 사용자에게 묻게 한다.
  - 파일 추가·삭제에는 이 파일을 고칠 일이 거의 없다. 폴더 단위로 파일을 참조해서다. 고칠 일은 패키지 연결, 타깃 추가, 빌드 설정 변경이다.

## 결과

- 좋아지는 점
  - xcodeproj 앱에 로컬 패키지로 모듈을 나눈 구성에서, verify가 바뀐 앱·패키지를 찾아 빌드·테스트한다.
  - 앱에 연결하기 전의 패키지도 같은 명령으로 빌드·테스트한다. 테스트를 아직 만들지 않은 패키지도 컴파일은 확인된다.
  - 매크로 신뢰에 막히면 원인과 할 일이 출력에 나온다.
- 비용과 위험
  - 앱에 연결한 패키지는 앱 빌드와 패키지 빌드·테스트에서 두 번 빌드된다. DerivedData를 따로 써서다.
  - 스킴을 고르느라 패키지를 돌릴 때마다 `xcodebuild -list`를 한 번 부른다(WorkoutRest에서 1초).
  - `skipMacroValidation`을 켜면 매크로 패키지를 바꿀 때도 신뢰 확인 없이 빌드된다.
- 다시 볼 때
  - Watch 앱을 붙이면 watchOS 시뮬레이터 선택과 detect를 다룬다.
