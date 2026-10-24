# Xcode build and Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the app with an XcodeGen-generated Xcode project so App Intents metadata ships, and add five Korean Shortcuts actions.

**Architecture:**
- `project.yml` generates `VibeBattery.xcodeproj` (committed) with three targets that compile the existing source folders against the local package's libraries.
- `AppModel.shared` is the single model, used by both SwiftUI and the intents.
- Writes from Shortcuts go through `ChargeController.apply(_:source:.shortcut)`.

**Tech Stack:** XcodeGen 2.46 (generation only), Xcode 27.1 locally / macos-15 runner in CI, AppIntents, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-23-xcode-shortcuts-design.md`

## Global Constraints

- Helper signing identifier stays `io.github.y-minion.vibebattery.helper`. The app identifier stays `io.github.y-minion.vibebattery`. Signing stays ad-hoc (`-`).
- Info.plist values stay as `build-app.sh` writes them today.
- `swift test`, `swift build` and `scripts/smoke-sessions.py` keep working from the package.
- The output is `dist/VibeBattery.app` plus `dist/VibeBattery.zip`. It is staged and signed outside synced folders, then copied with `ditto --norsrc --noextattr`. It must pass `codesign --verify --strict`.
- Shortcut text is Korean. The limit is 50…100 in steps of 5, default 80.

## Review Focus

1. CI's older Xcode must open the generated project. Set the XcodeGen `projectFormat` to one the macos-15 runner supports (Task 3: the CI run is the check).
2. The embedded `vbctl` and helper must carry the right identifiers (Task 3: `codesign -dv` checks in `build-app.sh`).
3. When an intent launches the app in the background, the model must exist before any write. `AppModel.shared` initializes lazily on first access (Task 2).
4. A Shortcut write must not raise "다른 곳에서 바뀜". It counts as a VibeBattery write: `source:.shortcut`, `byUser:true` (Task 2, reusing the controller tests' source logging).
5. The status action with no battery (desktop or CI) returns empty values, not a crash (Task 1: `statusWithoutBattery`).

---

### Task 1: Status report for Shortcuts and package product

**Files:**
- Create: `Sources/BatteryCore/ShortcutStatus.swift`
- Modify: `Package.swift` (add `.library(name: "MacBridge", targets: ["MacBridge"])`)
- Test: `Tests/BatteryCoreTests/ShortcutStatusTests.swift`

**Interfaces:**
- Produces:
  - `struct ShortcutStatus: Equatable, Sendable { percent: Int?; charging: Bool; onAC: Bool; limit: Int?; health: Int?; temperature: Double?; static func make(_ b: BatterySnapshot, limit: ChargeLimitState) -> ShortcutStatus; var summary: String }`
    - `limit` is nil unless `limit.enabled == true`.
    - `summary` example: `"배터리 82% · 충전 중 · 상한 70% · 건강도 88% · 31.5°C"`.
    - Missing parts: `"—%"`; `"충전 안 함"` or `"배터리 사용 중"` when not on AC; `"상한 없음"`; the health and temperature parts are dropped when nil.
- [ ] Step 1: write the tests, each asserting `make` and `summary`:
  - `statusMapsSnapshot`
  - `limitOffIsNil`
  - `statusWithoutBattery`: an empty snapshot gives `"배터리 —% · 배터리 사용 중 · 상한 없음"`
- [ ] Step 2: run `swift test --filter ShortcutStatusTests`. Expected: FAIL to compile.
- [ ] Step 3: implement.
- [ ] Step 4: run `swift test`. Expected: all pass.
- [ ] Step 5: commit `feat: summarize battery status for Shortcuts`.

### Task 2: Shared model and intents

**Files:**
- Create: `Sources/VibeBattery/ChargeIntents.swift`
- Modify: `Sources/VibeBattery/AppModel.swift`, `Sources/VibeBattery/App.swift`, `Sources/VibeBattery/SettingsView.swift`

**Interfaces:**
- Consumes: `ShortcutStatus`, `ChargeController.apply(_:source:)`, `AppModel.chargeMessage`.
- Produces:
  - `AppModel.shared` (`static let`, `@MainActor`). `App` uses `@StateObject private var model = AppModel.shared`.
  - `AppModel.perform(_ c: ChargeCommand, source: ChargeWrite.Source) -> ControlResponse`. It generalizes `handleControl`, which becomes `perform(c, source: .cli)`.
  - `AppModel.shortcutStatus() -> ShortcutStatus` (refreshes the battery first).
- Intents, each with `openAppWhenRun = false`:

| Intent | Title | Notes |
|---|---|---|
| `SetChargeLimitIntent` | "충전 상한 설정" | `@Parameter(title: "상한", default: 80, inclusiveRange: (50, 100)) var percent: Int`; rejects non-multiples of 5 with `ChargeError.invalid`'s text |
| `StartTopUpIntent` | "한 번 완충 시작" | |
| `EndTopUpIntent` | "완충 종료" | |
| `ClearChargeLimitIntent` | "충전 상한 끄기" | |
| `GetBatteryStatusIntent` | "배터리 상태 가져오기" | Returns `BatteryStatusEntity`, a `TransientAppEntity` with properties 잔량, 충전 중, 어댑터 연결, 상한, 건강도, 온도. Its display representation is `summary` |

  - Write intents call `AppModel.shared.perform(_, source: .shortcut)`. On `ok` they return a dialog with the message; otherwise they throw an error whose `localizedStringResource` is the message.
  - `VibeBatteryShortcuts: AppShortcutsProvider` registers 3 phrases with `\(.applicationName)`: "\(.applicationName) 상한 80%", "\(.applicationName) 한 번 완충" and "\(.applicationName) 배터리 상태".
- Settings card copy, per the spec: "단축어 앱에서 'VibeBattery'를 검색하면 전용 동작을 쓸 수 있습니다. 셸 스크립트 실행에 vbctl 명령을 넣어도 됩니다."
- [ ] Step 1: `swift build`. Expected: Build complete (the intents compile in the package build too).
- [ ] Step 2: `swift test`. Expected: all pass.
- [ ] Step 3: commit `feat: add Shortcuts actions backed by the app model`.

### Task 3: Xcode project and build script

**Files:**
- Create: `project.yml`, `VibeBattery.xcodeproj` (generated), `Resources/Info.plist` (or `info` properties in `project.yml`)
- Modify: `scripts/build-app.sh`, `.github/workflows/ci.yml` (CI keeps calling `scripts/build-app.sh`; add `xcodebuild -version` for the log), `README.md` (build section: Xcode is required; `xcodegen generate` after changing `project.yml`)

`build-app.sh` steps:
1. Run `xcodebuild -project VibeBattery.xcodeproj -scheme VibeBattery -configuration Release -derivedDataPath .build/xcode build`.
2. Copy the product into a temporary staging folder.
3. Re-sign: `vbctl` ad-hoc, the helper with `--identifier io.github.y-minion.vibebattery.helper`, then the app.
4. Run `codesign --verify --strict`.
5. Assert that `Contents/Resources/Metadata.appintents` exists, that `codesign -dv` of the helper prints the helper identifier, and that both scripts exist.
6. Copy to `dist/` with `ditto --norsrc --noextattr` and zip.

- [ ] Step 1: write `project.yml`, then run `xcodegen generate`.
- [ ] Step 2: run `scripts/build-app.sh | tail -1`. Expected: `dist/VibeBattery.app`.
- [ ] Step 3: run `ls dist/VibeBattery.app/Contents/Resources dist/VibeBattery.app/Contents/MacOS; codesign -dv dist/VibeBattery.app/Contents/MacOS/VBChargeHelper 2>&1 | grep ^Identifier; python3 scripts/smoke-sessions.py dist/VibeBattery.app/Contents/MacOS/vbctl | tail -1`. Expected: `Metadata.appintents`, the 2 scripts, `VibeBattery`, `vbctl` and `VBChargeHelper`; the helper identifier; smoke PASS.
- [ ] Step 4: commit `build: build the app with an Xcode project so Shortcuts actions ship`.

### Task 4: On-device check, docs, publish

- [ ] Install with `ditto` (quit the app first) and relaunch.
  - Check that `vbctl charge set 70` still returns exit 0. The limit is already 70%, so nothing changes.
  - Check that the helper is still reachable: the settings or charge page shows "헬퍼 사용 가능".
- [ ] The user searches "VibeBattery" in Shortcuts: 5 actions appear. They run "배터리 상태 가져오기", then "충전 상한 설정" with 70. The log shows source 단축어.
- [ ] Update `docs/VALIDATION.md` (Xcode build and Shortcuts section), the `docs/COMPATIBILITY.md` row and `README.md` features. Commit `docs: record Xcode build and Shortcuts validation`.
- [ ] Push `feat/xcode-shortcuts`, open a PR to `main`, and check that CI passes.
