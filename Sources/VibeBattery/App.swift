import SwiftUI
import AppKit
import BatteryCore
import BatteryPlatform
@main struct VibeBatteryApp: App {
    @StateObject private var model=AppModel.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body:some Scene {
        WindowGroup("VibeBattery",id:"main") { RootView().environmentObject(model).frame(minWidth:900,minHeight:650).tint(.mint) }
            .defaultSize(width:1050,height:740)
        MenuBarExtra {
            MenuContent().environmentObject(model)
        } label: { MenuLabel().environmentObject(model) }
    }
}
/// Always rendered, so it is where the app keeps a way to reopen the window for notification clicks.
struct MenuLabel:View {
    @EnvironmentObject var model:AppModel
    @Environment(\.openWindow) var openWindow
    var body:some View {
        Label("\(model.battery.percent.map(String.init) ?? "—")%",systemImage:model.battery.onAC ? "bolt.batteryblock":"battery.75percent")
            .onAppear { model.openMain={ openWindow(id:"main") } }
    }
}
struct MenuContent:View {
    @EnvironmentObject var model:AppModel
    @Environment(\.openWindow) var openWindow
    var body:some View {
        Text("VibeBattery · \(model.battery.percent.map(String.init) ?? "—")%")
        Text(model.battery.temperature.map { String(format:"배터리 %.1f°C",$0) } ?? "온도 조회 불가")
        Text(ChargeText.limit(model.charge)+(model.nextSchedule.map { " · 다음 일정 "+ScheduleText.when($0.at,now:Date(),calendar:.current) } ?? ""))
        let canWrite=model.charge.supported==true && model.chargeConflicts.isEmpty
        if model.topUpActive { Button("완충 종료") { model.applyCharge(.endTopUp) }.disabled(!canWrite) }
        else { Button("한 번 100% 충전") { model.applyCharge(.startTopUp) }.disabled(!canWrite) }
        Divider()
        Button("대시보드 열기") { openWindow(id:"main");NSApp.activate(ignoringOtherApps:true) }
        Button("Claude 실행 명령 복사") { model.copyCommand("claude") }
        Button("Codex 실행 명령 복사") { model.copyCommand("codex") }
        Button("배터리 설정 열기") { model.openBatterySettings() }
        Divider()
        Button("앱 종료") { NSApp.terminate(nil) }
    }
}
struct RootView:View {
    @EnvironmentObject var model:AppModel
    private let items=[("dashboard","대시보드","square.grid.2x2"),("charge","충전","bolt.batteryblock"),("health","건강 분석","heart.text.square"),("processes","앱과 프로세스","waveform.path.ecg"),("sessions","바이브 코딩","terminal"),("settings","설정","slider.horizontal.3")]
    var body:some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:26) {
                HStack { Image(systemName:"leaf.fill").foregroundStyle(.mint); Text("VibeBattery").font(.title3.bold()) }.padding(.top,24)
                VStack(spacing:8) {
                    ForEach(items,id:\.0) { item in
                        Button { model.section=item.0 } label: {
                            Label(item.1,systemImage:item.2).font(.system(size:14,weight:.medium)).frame(maxWidth:.infinity,alignment:.leading).padding(12)
                                .background(model.section==item.0 ? Color.mint.opacity(0.14):Color.clear,in:RoundedRectangle(cornerRadius:10))
                        }.buttonStyle(.plain).foregroundStyle(model.section==item.0 ? Color.mint:Color.primary)
                    }
                }
                Spacer()
                Label("로컬 저장 · 무료 · 오픈소스",systemImage:"lock.shield").font(.caption).foregroundStyle(.secondary)
                Text("개발 미리보기 0.1").font(.caption2).foregroundStyle(.tertiary).padding(.bottom,20)
            }.padding(.horizontal,16).frame(width:210).background(.ultraThinMaterial)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    switch model.section {
                    case "charge":ChargeView()
                    case "health":HealthView()
                    case "processes":ProcessesView()
                    case "sessions":SessionsView()
                    case "settings":SettingsView()
                    default:DashboardView()
                    }
                }.padding(30).frame(maxWidth:.infinity,alignment:.leading)
            }.background(Color(nsColor:.windowBackgroundColor))
        }.alert("VibeBattery",isPresented:Binding(get:{model.message != nil},set:{if !$0 {model.message=nil}})) { Button("확인") { model.message=nil } } message: { Text(model.message ?? "") }
    }
}
struct Card<Content:View>:View {
    @ViewBuilder var content:Content
    var body:some View { VStack(alignment:.leading,spacing:14) { content }.frame(maxWidth:.infinity,alignment:.leading).padding(22).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).strokeBorder(Color.primary.opacity(0.06))) }
}
struct PageTitle:View {
    var title:String;var subtitle:String
    var body:some View { VStack(alignment:.leading,spacing:8) { Text(title).font(.system(size:30,weight:.bold));Text(subtitle).font(.callout).foregroundStyle(.secondary) } }
}
