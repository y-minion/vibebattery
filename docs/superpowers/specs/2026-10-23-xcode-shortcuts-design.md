# Xcode 빌드 전환과 단축어 전용 동작 설계

작성일: 2026-10-23 · 하위 프로젝트 3-1 (순서: 3-1 → 3-2 자동화(완료) → 3-3 Pro 기능 무료화 → 3-4 배포)

사용자 지시: "순차적으로 모두 작업해." 질문 없이 진행하고, 이 문서의 결정은 모두 작성자 판단이다.

## 의도

- 단축어 앱에서 VibeBattery를 검색하면 전용 동작이 보이게 한다. AlDente Pro의 유료 Shortcuts 기능을 무료로 제공하는 것이다.
- 빌드를 Xcode 기반으로 옮긴다. 3-4에서 Developer ID 서명과 공증을 할 수 있고, Command Line Tools 업데이트로 빌드가 깨지던 문제도 사라진다.

## 확인한 사실 (2026-10-23 시험)

- Swift 패키지의 실행 대상은 `xcodebuild`로 빌드해도 `Metadata.appintents`가 만들어지지 않는다. 그래서 단축어 동작이 나타나지 않는다.
- XcodeGen으로 만든 앱 대상(`type: application`)은 Release 빌드에서 `Contents/Resources/Metadata.appintents`를 만든다. 로컬 Swift 패키지의 라이브러리도 연결된다.
- (설치 후 확인, 2026-10-24) 단축어 앱은 팀 서명이 있는 앱의 동작만 보여 준다. 임시 서명 앱은 `Metadata.appintents`가 있어도 동작이 보이지 않는다. 그래서 `build-app.sh`는 키체인의 "Apple Development" 인증서(또는 `VB_SIGN_IDENTITY`)로 서명하고, 인증서가 없을 때(CI 등)만 임시 서명으로 빌드한다. 헬퍼는 식별자만 확인하므로 두 서명 모두에서 동작한다.

## 목표

1. 저장소 루트의 `project.yml`(XcodeGen)이 `VibeBattery.xcodeproj`를 만든다. 생성된 프로젝트도 커밋해서, 사용자와 CI는 XcodeGen 없이 빌드한다.
   - 대상 1, `VibeBattery`: 앱. 소스는 `Sources/VibeBattery`이고 패키지 제품 `BatteryCore`, `BatteryPlatform`에 의존한다.
   - 대상 2, `vbctl`: 명령줄 도구. 소스는 `Sources/VibeCLI`이고 `BatteryCore`, `BatteryPlatform`, `MacBridge`에 의존한다.
   - 대상 3, `VBChargeHelper`: 명령줄 도구. 소스는 `Sources/VBChargeHelper`이고 같은 의존성에 `SystemConfiguration`을 더한다. 서명 식별자는 `io.github.y-minion.vibebattery.helper`다.
   - 앱은 `vbctl`과 `VBChargeHelper`를 `Contents/MacOS`에, `install-helper.sh`와 `uninstall-helper.sh`를 `Contents/Resources`에 넣는다.
   - Info.plist 값은 지금 `build-app.sh`와 같다:
     - 식별자 `io.github.y-minion.vibebattery`, 이름 VibeBattery
     - 버전 0.1.0 (1)
     - 최소 macOS 15.0
     - 고해상도 지원
   - 서명은 지금처럼 임시(ad-hoc) 서명이다. 3-4에서 Developer ID로 바꾼다.
2. `scripts/build-app.sh`는 `xcodebuild`(Release, 파생 데이터는 `.build/xcode`)로 앱을 만든다. 결과물은 지금처럼 `dist/VibeBattery.app`과 `dist/VibeBattery.zip`이다. 기존 엄격 서명 검사와 iCloud 대비 복사 방식은 유지한다.
3. Swift 패키지는 유지한다. `swift test`와 `swift build`, 세션 스모크 테스트는 지금처럼 돈다. 패키지에 `MacBridge` 라이브러리 제품을 추가한다.
4. **단축어 동작**(App Intents, 앱 대상 안). 이름과 설명은 한국어다.

| 동작 | 입력과 결과 |
|---|---|
| 충전 상한 설정 | 매개변수 "상한"은 50~100, 5 단위, 기본값 80 |
| 한 번 완충 시작 | |
| 완충 종료 | |
| 충전 상한 끄기 | |
| 배터리 상태 가져오기 | 잔량, 충전 중 여부, 어댑터 연결, 현재 상한(꺼짐이면 없음), 건강도(추정), 온도를 담은 결과. 단축어에서 각 값을 꺼내 쓸 수 있다 |

   - 쓰기 동작 넷은 앱의 `ChargeController.apply(_:source:.shortcut)`를 거친다. 결과 문구는 앱 메시지와 같다.
   - 실패하면 단축어 오류로 그 문구를 보인다.
   - 상한 값이 5 단위가 아니면 "충전 상한은 50~100% 사이에서 5% 단위로 고를 수 있습니다."로 거절한다.
   - 앱이 꺼져 있을 때 단축어를 실행하면, 시스템이 앱을 백그라운드로 띄우고 실행한다(`openAppWhenRun = false`).
   - 단축어 동작이 앱 모델에 닿도록 `AppModel.shared` 하나만 쓴다. SwiftUI 앱도 그 인스턴스를 쓴다.
   - App Shortcuts 문구(한국어) 3개를 등록한다:
     - "VibeBattery 상한 80%"
     - "VibeBattery 한 번 완충"
     - "VibeBattery 배터리 상태"

     Siri와 Spotlight 노출은 macOS가 정한다.
5. 설정의 "명령줄과 단축어" 카드 문구를 바꾼다: "단축어 앱에서 'VibeBattery'를 검색하면 전용 동작을 쓸 수 있습니다. 셸 스크립트 실행에 vbctl 명령을 넣어도 됩니다."

## 하지 않는 것

- Developer ID 서명, 공증, 배포(3-4).
- 단축어 동작으로 일정을 편집하는 기능.
- 패키지에서 앱 실행 대상을 지우는 것. CI의 컴파일 확인에 쓰므로 남겨 둔다.

## 실패로 보는 것

- Xcode로 빌드한 앱에서 헬퍼, `vbctl`, 세션, 알림 중 하나라도 동작하지 않는 것. 헬퍼 서명 식별자가 달라져 헬퍼가 요청을 거절하는 경우도 포함한다.
- 단축어 쓰기가 "외부 변경"으로 오인되는 것.
- CI가 Xcode 버전 차이로 깨지는 것. CI는 macos-15 러너이고 Xcode 버전이 다르다. 생성한 프로젝트의 형식은 CI의 Xcode가 열 수 있어야 한다.

## 검증

- 단위 테스트:
  - 상태 결과를 만드는 순수 함수(꺼진 상한은 없음, 센서 없음 처리)
  - 상한 값 검증
- 빌드:
  - 로컬에서 `scripts/build-app.sh` 결과 앱에 아래가 모두 있는지 확인한다.
    - `Metadata.appintents`
    - `vbctl`과 `VBChargeHelper`, 그리고 헬퍼 식별자
    - 스크립트 2개
  - `codesign --verify --strict` 통과
  - 내장 `vbctl`로 세션 스모크 테스트
- CI: 같은 스크립트가 러너에서 통과한다.
- 실기기:
  - 설치 후 단축어 앱에서 "VibeBattery"를 검색하면 동작 5개가 보인다(사용자).
  - "배터리 상태 가져오기"가 값을 돌려준다.
  - "충전 상한 설정 70"(현재 값과 같은 값)이 적용되고 기록 출처가 "단축어"다.
  - 헬퍼를 거치는 80% 미만 쓰기가 성공한다. 서명 식별자가 유지되는지 확인하는 것이다.
