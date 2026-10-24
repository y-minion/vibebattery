# VibeBattery

**무료·오픈소스 macOS 배터리 관리와 터미널 코딩 작업 도우미.**

개발 미리보기입니다. M4 Pro / macOS 27.0.1에서 먼저 검증합니다. 모든 AlDente 기능을 구현한 상태가 아닙니다. [지원 현황과 제약](docs/COMPATIBILITY.md)을 확인하세요.

## 현재 기능

- 실제 배터리 잔량·용량 기반 건강도·사이클·온도·충방전 전력
- CPU 활동 기반 프로세스 목록과 사용자 선택 앱 종료 (일반 백그라운드 프로세스는 활성 상태 보기로 연결)
- 로컬에 저장하는 선택적 7일 이력
- 등록한 터미널 작업 동안 화면 끄기와 제한된 잠자기 방지
- 작업 성공 후 명시적으로 등록한 임시 프로세스만 정상 종료
- iTerm2와 Ghostty에서 기존 Claude/Codex 명령을 감싸 실행하는 CLI
- 충전 상한 50~100% (80% 미만은 선택 설치하는 헬퍼 필요), 적용 후 다시 읽어 확인
- 한 번만 100% 충전 (끝나면 앱이 마지막으로 정한 상한을 다시 적용)
- 충전 일정: 요일·시각마다 상한 바꾸기, 한 번 완충, 상한 끄기. 맥이 잠들어 놓친 일정은 12시간 안이면 깨어날 때 가장 최근 것 하나만 실행. 상한이 바뀔 때마다 언제, 무엇 때문에 바뀌었는지 표시
- 명령줄 충전 제어(`vbctl charge set|off|topup|end|status`): 실행 중인 앱을 거쳐 적용되므로 단축어의 "셸 스크립트 실행"에서도 50~100%를 쓸 수 있음
- 단축어 전용 동작: 충전 상한 설정, 한 번 완충 시작, 완충 종료, 충전 상한 끄기, 배터리 상태 가져오기(잔량·충전 중·어댑터·상한·건강도 추정·온도). 앱이 꺼져 있으면 macOS가 백그라운드로 띄워 실행
- 과열 시 충전 보류 (선택, 앱 실행 중)
- AlDente·batt 등 다른 충전 관리 앱 감지 시 모든 변경 차단
- 건강 분석: 하루 단위 충전 습관 기록(최대 1년, 이 맥에만 저장), 실측 건강도 추세로 80% 도달 시기를 범위로 추정(30일 이상 기록 후), 잔량·온도 기반 상대 스트레스와 "상한 80%였다면" 비교, 잠자기 중 소모, 규칙 기반 제안. `vbctl health [--json]`
- 로컬 알림: 충전 상한 도달·꺼짐·외부 변경, 완충 끝남, 배터리 부족, 고온, 과열 보류 문제, 다른 충전 관리 앱, 바이브 코딩 작업 종료·잠자기 방지 해제, 잠자기 중 소모, 새 제안, 주간 요약. 이벤트별로 켜고 끄며 같은 상황은 한 번만 알림(앱 실행 중에만, 권한은 설정 화면에서 요청)

macOS 27 펌웨어(20457.1.29)는 SMC 충전 중지 키를 막고 있어, 충전 상한은 macOS 기본 충전 상한 기능을 통해 적용합니다. 상한은 앱을 종료해도, 잠자기·재시동 후에도 macOS가 유지합니다. 충전기가 연결되어 있어도 잔량이 상한보다 높으면 macOS가 배터리를 써서 상한까지 내린 뒤, 그때부터는 충전기 전원으로 동작합니다. 항해의 재충전 하한 지정·강제 방전·교정은 어댑터 전원 차단 없이 불가능해 제공하지 않으며, MagSafe LED는 아직 지원하지 않습니다. 에너지 모드는 macOS 배터리 설정으로 연결합니다. 실제 쓰기 검증 현황은 [검증 기록](docs/VALIDATION.md)을 확인하세요.

## 빌드

Xcode가 필요합니다. 앱은 저장소의 `VibeBattery.xcodeproj`로 빌드합니다. 이 프로젝트는 `project.yml`에서 [XcodeGen](https://github.com/yonaskolb/XcodeGen)으로 만들었으므로, `project.yml`을 고친 뒤에는 `xcodegen generate`를 실행하세요. 테스트는 Swift 패키지로 돌립니다.

```sh
swift test --disable-xctest
python3 scripts/smoke-sessions.py .build/debug/vbctl
scripts/build-app.sh
open dist/VibeBattery.app
```

빌드 결과는 `dist/VibeBattery.app`과 `dist/VibeBattery.zip`입니다. 단축어 전용 동작은 Xcode 빌드에만 포함됩니다. 단축어 앱은 팀 서명이 있는 앱의 동작만 보여 주므로, 빌드 스크립트는 키체인의 "Apple Development" 인증서(또는 `VB_SIGN_IDENTITY`로 지정한 인증서)로 서명합니다. 인증서가 없으면 임시 서명으로 빌드하고, 이때는 단축어 앱에 동작이 보이지 않습니다. 일반 배포용 Developer ID 서명·공증은 아직 포함하지 않습니다. 현재 저장소에는 원본 코드만 있고 외부 패키지 의존성은 없습니다.

## 명령줄과 단축어

앱이 실행 중이어야 합니다. 앱만 충전 설정을 쓰고, 명령줄은 같은 사용자만 쓸 수 있는 로컬 통로로 앱에 요청합니다.

```sh
VB=/Applications/VibeBattery.app/Contents/MacOS/vbctl
$VB charge set 70          # 50~100, 5 단위
$VB charge off             # 상한 끄기
$VB charge topup           # 한 번 100% 충전
$VB charge end             # 진행 중인 완충 끝내기
$VB charge status --json   # 앱 없이도 읽기
```

종료 코드는 0(성공), 1(적용 실패 또는 결과 미확인), 2(사용법 오류), 3(앱이 실행 중이 아님)입니다. 단축어 앱에서 "VibeBattery"를 검색하면 전용 동작 5개를 쓸 수 있고, 이 동작의 쓰기는 충전 기록에 "단축어"로 남습니다.

## 충전 헬퍼 (선택)

80% 미만 상한에만 필요합니다. 앱을 `/Applications`에 복사한 뒤 설치합니다. 저장소가 iCloud 동기화 폴더(예: `~/Documents`)에 있으면 macOS가 Finder 정보를 붙여 서명 검사가 실패하므로, 확장 속성 없이 복사합니다. 헬퍼는 현재 로그인 사용자가 실행한 `/Applications/VibeBattery.app`의 요청만 받고, 충전 상한 값 쓰기와 상태 읽기 외의 기능은 없습니다.

```sh
ditto --norsrc --noextattr dist/VibeBattery.app /Applications/VibeBattery.app
sudo /Applications/VibeBattery.app/Contents/Resources/install-helper.sh
sudo /Applications/VibeBattery.app/Contents/Resources/uninstall-helper.sh   # 제거, 현재 상한은 유지
```

다른 충전 관리 앱(AlDente, batt, battery, Battery Toolkit)이 실행 중이거나 설치되어 있으면 VibeBattery는 값을 바꾸지 않습니다.

현재 빌드는 임시(ad-hoc) 서명이라, 헬퍼의 호출자 확인은 보안 경계가 아닙니다. 같은 사용자 권한의 프로그램이 상한(50~100%)을 바꿀 수 있습니다. 앱은 자신이 시도한 충전 설정 쓰기를 최근 20건까지 `charge.json`에 시각·명령·요청 주체(사용자, 과열 보류, 앱 종료, 완충 후 복원)와 함께 기록합니다. 설치 스크립트는 사용자가 쓸 수 있는 앱 번들 안에 있으므로, 직접 빌드했거나 내용을 확인한 사본만 sudo로 실행하세요.

## 터미널 작업

앱의 **바이브 코딩** 화면에서 명령을 복사할 수 있습니다. 또는 빌드한 CLI를 직접 사용하세요.

```sh
.build/debug/vbctl status
.build/debug/vbctl run --hours 4 --screen-off -- claude
.build/debug/vbctl run --hours 4 --screen-off -- codex
.build/debug/vbctl sessions
.build/debug/vbctl release SESSION_UUID
```

명령 인수는 셸 문자열로 다시 해석하지 않습니다. 기존 터미널 입력/출력과 로그인 환경을 사용합니다. AI 대화, 명령 인수, 출력, API 키는 저장하지 않습니다.

시간 만료 또는 어댑터 분리 시 기본적으로 **보호만 해제**합니다. 실행 중인 명령은 종료하지 않지만 macOS가 잠들 수 있습니다. 화면을 보며 조작하는 AI는 별도 호환성 검증이 필요합니다. 화면 끄기는 시스템 잠자기나 잠금 정책 해제와 다릅니다.

## 명시적 임시 리소스 정리

자동 정리는 기본적으로 꺼져 있습니다. `--cleanup`으로 시작한 관리 세션 안에서 다음 형태로 생성한 **작업 전용 임시 리소스**만 대상입니다.

```sh
/path/to/vbctl resource -- python3 -m http.server 8000
/path/to/vbctl resource --keep -- python3 -m http.server 8001
```

명령은 `VIBEBATTERY_SESSION` 환경을 상속해야 합니다. 필요하면 터미널에서 리소스를 백그라운드로 실행할 수 있습니다. 성공한 주 작업이 종료되면 등록된 리소스에 SIGTERM을 보냅니다. 실패·취소·보호 해제·시간 만료에는 자동 정리하지 않습니다. 응답하지 않아도 자동 강제 종료하지 않습니다. 공유할 서버는 반드시 `--keep`을 사용하세요. 일반 프로세스를 이름만 보고 종료하거나 파일을 삭제하지 않습니다.

기록은 `~/Library/Application Support/VibeBattery`에만 저장합니다. `VIBEBATTERY_DATA_DIR`는 테스트용 데이터 경로를 분리할 때 사용할 수 있습니다.
종료된 세션 기록은 앱 갱신 또는 새 세션 시작 시 30일 기준으로 정리합니다. 설정에서 즉시 삭제할 수도 있으며 실행 중인 관리 세션은 보존합니다.

## 개발

설계와 계획은 [docs/superpowers](docs/superpowers)에 있습니다. 공개 기록에 개인 기기의 원본 센서 덤프나 대화 내용을 올리지 않습니다.

MIT · [라이선스](LICENSE) · [참고 프로젝트](THIRD_PARTY_NOTICES.md)
