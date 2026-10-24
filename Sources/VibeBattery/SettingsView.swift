import SwiftUI
import BatteryCore
struct SettingsView:View {
    @EnvironmentObject var model:AppModel
    var accessText:String {
        switch model.notificationAccess {
        case .allowed:return "알림 허용됨"
        case .denied:return "알림이 거부되어 있습니다"
        case .notAsked:return "알림 권한을 아직 묻지 않았습니다"
        case .unavailable:return "개발 실행이라 알림을 쓸 수 없습니다"
        }
    }
    func flag(_ title:String,_ detail:String,_ key:WritableKeyPath<NotificationSettings,Bool>) -> some View {
        Toggle(isOn:Binding(get:{ model.preferences.notifications[keyPath:key] },set:{ model.preferences.notifications[keyPath:key]=$0;model.savePreferences() })) {
            VStack(alignment:.leading,spacing:2) { Text(title);Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
    var body:some View {
        PageTitle(title:"설정",subtitle:"앱 전체 설정과 알림, 기록을 정합니다. 충전 관련 설정은 충전 페이지에 있습니다.")
        Card {
            Text("알림").font(.headline)
            HStack {
                Text(accessText).foregroundStyle(.secondary);Spacer()
                if model.notificationAccess == .notAsked { Button("알림 허용") { model.requestNotifications() } }
                if model.notificationAccess == .denied { Button("시스템 설정 열기") { model.openNotificationSettings() } }
                Button("테스트 알림 보내기") { model.sendTestNotification() }.disabled(model.notificationAccess != .allowed)
            }
            Text("충전 상태").font(.subheadline.weight(.semibold))
            flag("충전 상한 도달","충전 중 상한에 닿아 충전이 멈추면",\.limitReached)
            flag("완충 끝남","한 번 완충이 99% 이상이 되면",\.topUpDone)
            flag("일정 실행 실패","일정이 상한을 바꾸지 못했을 때",\.scheduleFailed)
            flag("일정 실행됨","일정이 실행될 때마다",\.scheduleRan)
            flag("배터리 부족","배터리 사용 중 아래 기준 이하로 내려가면",\.lowBattery)
            Stepper("배터리 부족 기준 \(model.preferences.notifications.lowAt)%",value:$model.preferences.notifications.lowAt,in:NotificationSettings.lowRange,step:5).onChange(of:model.preferences.notifications.lowAt) { _,_ in model.savePreferences() }
            flag("충전 상한이 꺼지거나 바뀜","VibeBattery가 설정한 상한을 다른 곳에서 바꾸면",\.limitChanged)
            flag("충전 제어 불가","macOS가 충전 상한 기능을 더 이상 제공하지 않으면",\.controlUnavailable)
            Text("보호 경고").font(.subheadline.weight(.semibold))
            flag("배터리 고온","아래 기준 이상(배터리 사용 중에는 +2°C)이면",\.highTemperature)
            Stepper("고온 기준(충전 중) \(Int(model.preferences.notifications.hotAt))°C",value:$model.preferences.notifications.hotAt,in:NotificationSettings.hotRange,step:1).onChange(of:model.preferences.notifications.hotAt) { _,_ in model.savePreferences() }
            flag("다른 충전 관리 앱 감지","AlDente 등이 감지되어 변경을 막으면",\.conflict)
            flag("과열 보류 문제","복원 실패, 멈춤, 적용 실패, 온도 센서 없음",\.heatProblem)
            flag("과열 보류 시작·해제","보류를 걸거나 풀 때마다",\.heatActivity)
            Text("바이브 코딩").font(.subheadline.weight(.semibold))
            flag("작업 종료","실행 파일 이름과 걸린 시간만 표시",\.sessionEnded)
            flag("작업 취소","Ctrl‑C 등으로 취소한 작업",\.sessionCancelled)
            flag("잠자기 방지 해제","어댑터 분리나 시간 만료로 보호가 풀리면",\.protectionReleased)
            Text("건강 분석").font(.subheadline.weight(.semibold))
            flag("잠자기 중 배터리 소모","깨어났을 때 시간당 소모가 크면",\.sleepDrain)
            flag("새 제안","같은 제안은 7일에 한 번",\.suggestions)
            flag("주간 요약","월요일 09:00 이후 첫 측정 때",\.weeklySummary)
            Text("앱이 실행 중일 때만 알리며 최대 2분 늦을 수 있습니다. 집중 모드에서는 가려질 수 있고, 잠금 화면 미리보기는 macOS 알림 설정을 따릅니다.").font(.caption).foregroundStyle(.secondary)
        }.onAppear { model.checkNotifications() }
        Card {
            Text("명령줄과 단축어").font(.headline)
            Text("앱이 실행 중이면 터미널이나 단축어에서 충전 상한을 바꿀 수 있습니다.").foregroundStyle(.secondary)
            VStack(alignment:.leading,spacing:4) {
                ForEach(["vbctl charge set 70","vbctl charge topup","vbctl charge status --json"],id:\.self) { Text($0).font(.system(.callout,design:.monospaced)).textSelection(.enabled) }
            }
            Button("vbctl 경로 복사") { model.copyText(Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/vbctl").path) }
            Text("단축어 앱에서 'VibeBattery'를 검색하면 전용 동작을 쓸 수 있습니다. 셸 스크립트 실행에 vbctl 명령을 넣어도 됩니다.").font(.caption).foregroundStyle(.secondary)
        }
        Card {
            Text("시작과 에너지 모드").font(.headline)
            Toggle("로그인 시 VibeBattery 실행",isOn:Binding(get:{ model.loginItem },set:{ model.setLoginItem($0) }))
            Text("저전력·자동·고전력 모드는 macOS 배터리 설정에서 선택합니다.").foregroundStyle(.secondary)
            Button("시스템 배터리 설정 열기") { model.openBatterySettings() }
        }
        Card {
            Text("기록과 개인정보").font(.headline)
            Toggle("배터리 이력 기록 (잔량 7일 · 건강 분석 1년)",isOn:$model.preferences.backgroundHistory).onChange(of:model.preferences.backgroundHistory) { _,_ in model.savePreferences() }
            Text("측정값은 이 맥에 저장합니다. AI 대화, 명령 인수, 터미널 출력, API 키는 기록하지 않습니다.").foregroundStyle(.secondary)
            Button("배터리 이력 삭제",role:.destructive) { model.clearHistory() }
            Text("종료된 세션 기록은 앱 실행 중 최대 30일간 보관합니다. 실행 중인 관리 세션은 삭제하지 않습니다.").font(.callout).foregroundStyle(.secondary)
            Button("종료된 세션 기록 삭제",role:.destructive) { model.clearInactiveSessions() }
        }
        Card {
            Text("검증된 기능과 개발 중인 기능").font(.headline)
            Text("현재 제공: 배터리·온도 조회, CPU 활동 목록, 선택 종료, 이력, 터미널 작업 보호와 제한된 리소스 정리, 충전 상한 50~100%, 한 번 완충, 충전 일정, 명령줄 충전 제어, 건강 분석, 알림.").foregroundStyle(.secondary)
            Text("이 Mac에서 실기기 확인: 충전 상한, 한 번 완충, 알림. 실제 고온 상황의 과열 보류는 아직 확인 전입니다. 미제공: 항해 하한 지정·강제 방전·교정(펌웨어 제약). 개발 예정: 단축어 전용 동작, 전력 흐름, MagSafe LED.").foregroundStyle(.secondary)
            Link("GitHub에서 소스와 진행 상황 보기",destination:URL(string:"https://github.com/y-minion/vibebattery")!)
        }
    }
}
