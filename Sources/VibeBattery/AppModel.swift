import Foundation
import AppKit
import Combine
import ServiceManagement
import BatteryCore
import BatteryPlatform
@MainActor final class AppModel: ObservableObject {
    /// The one model, shared by the SwiftUI app and Shortcuts actions (which may launch the app in the background).
    static let shared=AppModel()
    func shortcutStatus() -> ShortcutStatus {
        battery=BatteryReader.read();refreshCharge()
        return ShortcutStatus.make(battery,limit:charge)
    }
    @Published var battery=BatterySnapshot()
    @Published var history:[BatterySnapshot]=[]
    @Published var processes:[ProcessSample]=[]
    @Published var sessions:[SessionRecord]=[]
    @Published var preferences=UserPreferences()
    @Published var message:String?
    @Published var section="dashboard"
    @Published var sampled=false
    @Published var charge=ChargeLimitState()
    @Published var chargeConflicts:[OtherChargeController]=[]
    @Published var loginItem=false
    @Published var helperStatus=HelperStatus.notInstalled
    @Published var healthReport:HealthReport?
    @Published var sleeps:[SleepEvent]=[]
    @Published var notificationAccess=NotificationAccess.unavailable
    var openMain:(()->Void)?
    private let notifier=NotificationRuntime.makeSink()
    private let notificationStore=NotificationStore(url:AppPaths.notify)
    private lazy var notificationMemory=notificationStore.read()
    private var pendingHeatEvent:HeatEvent?
    private lazy var healthRecorder=HealthRecorder(store:HealthStore(url:AppPaths.health))
    private let sleepStore=SleepStore(url:AppPaths.sleep)
    private var sleepStart:BatterySnapshot?
    private var trendCache=TrendCache()
    private let helper=XPCChargeHelper()
    private var lastHeatAction=HeatAction.none
    private lazy var chargeController=ChargeController(backend:PowerUIChargeBackend(),helper:helper,detect:ChargeControllerScan.current,url:AppPaths.directory.appendingPathComponent("charge.json"))
    var chargeOrigin:LimitOrigin { charge.origin(lastWritten:chargeController.record.lastWritten) }
    var topUpRequested:Date? { chargeController.record.topUpRequested }
    var topUpActive:Bool { chargeController.topUpActive }
    @Published var scheduleRuns:[ScheduleRun]=[]
    @Published var nextSchedule:ScheduleOccurrence?
    /// "22:00 일정 '밤에는 70%'로 바뀜": why the limit is what it is.
    var lastChangeText:String? { ChargeText.currentReason(record:chargeController.record,state:charge,now:Date(),calendar:.current) }
    var chargeLog:[ChargeWrite] { chargeController.record.log }
    private lazy var scheduleRunner=ScheduleRunner(file:JSONFile(url:AppPaths.schedule)) { [weak self] command,rule in
        MainActor.assumeIsolated { self?.runSchedule(command,rule) ?? .failed("앱을 사용할 수 없습니다.") }
    }
    private var controlServer:ControlServer?
    private func runSchedule(_ command:ChargeCommand,_ rule:ChargeScheduleRule) -> ScheduleApplyResult {
        switch chargeController.apply(command,source:.schedule,detail:rule.name) {
        case .success(let s):charge=s;return .applied
        case .failure(let e):return .failed(e.localizedDescription)
        }
    }
    func checkSchedules() {
        let run=scheduleRunner.check(preferences.schedules,now:Date(),calendar:.current)
        scheduleRuns=scheduleRunner.state.recent
        nextSchedule=SchedulePolicy.nextAny(preferences.schedules,after:Date(),calendar:.current)
        guard let run else { return }
        switch run.result {
        case .failed(let reason) where preferences.notifications.scheduleFailed:
            notifier.deliver(AlertEvent(id:"schedule.failed",title:"일정 '\(run.ruleName)' 실행 실패",body:reason,section:"charge",thread:"charge"))
        case .ran where preferences.notifications.scheduleRan:
            notifier.deliver(AlertEvent(id:"schedule.ran",title:"일정 '\(run.ruleName)' 실행됨",body:run.action,section:"charge",thread:"charge"))
        default:break
        }
    }
    func addSchedule(_ rule:ChargeScheduleRule) {
        guard preferences.schedules.count<SchedulePolicy.maxRules else { return }
        var r=rule;r.edited(now:Date());preferences.schedules.append(r);schedulesChanged()
    }
    /// Changing when or what a rule does, or turning it back on, starts it fresh so a time already past today does not fire.
    func updateSchedule(_ rule:ChargeScheduleRule) {
        guard let i=preferences.schedules.firstIndex(where:{ $0.id==rule.id }) else { return }
        let old=preferences.schedules[i];var r=rule
        if old.hour != r.hour || old.minute != r.minute || old.weekdays != r.weekdays || old.action != r.action || (!old.enabled && r.enabled) { r.edited(now:Date()) }
        preferences.schedules[i]=r;schedulesChanged()
    }
    func removeSchedule(id:UUID) { preferences.schedules.removeAll { $0.id==id };schedulesChanged() }
    private func schedulesChanged() {
        savePreferences()
        nextSchedule=SchedulePolicy.nextAny(preferences.schedules,after:Date(),calendar:.current)
    }
    static func chargeMessage(_ c:ChargeCommand,_ s:ChargeLimitState) -> String {
        c == .startTopUp ? "한 번 완충을 요청했습니다. 원래 상한으로 돌아가는 시점은 macOS가 정합니다.":"적용을 확인했습니다. \(ChargeText.limit(s))"
    }
    /// A request from vbctl or Shortcuts; applied like a user change and logged with its source.
    func perform(_ c:ChargeCommand,source:ChargeWrite.Source) -> ControlResponse {
        switch chargeController.apply(c,source:source) {
        case .success(let s):charge=s;return ControlResponse(ok:true,message:Self.chargeMessage(c,s),state:s)
        case .failure(let e):
            if c.requiresHelper { checkHelper() }
            return ControlResponse(ok:false,message:e.localizedDescription,state:charge)
        }
    }
    private func startControlServer() {
        try? FileManager.default.createDirectory(at:AppPaths.directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let server=ControlServer(path:AppPaths.controlSocket) { [weak self] c in
            MainActor.assumeIsolated { self?.perform(c,source:.cli) ?? ControlResponse(ok:false,message:"앱을 사용할 수 없습니다.",state:nil) }
        }
        // Without the channel only vbctl writes are unavailable; the app itself keeps working.
        do { try server.start();controlServer=server } catch { controlServer=nil }
    }
    func checkHelper() { helperStatus=helper.status() }
    func updateHealthReport() {
        let days=healthRecorder.file.days,now=Date()
        let trend=trendCache.trend(for:BatterySegment.current(days),now:now,calendar:.current)
        healthReport=HealthReport.make(snapshot:battery,days:days,sleeps:sleeps,context:AdvisorContext(limit:charge.enabled==true ? charge.limit:nil,heatEnabled:preferences.heat.enabled),now:now,calendar:.current,trend:trend)
    }
    func clearHealth() {
        do { try healthRecorder.reset();try sleepStore.delete();sleeps=[];updateHealthReport() } catch { message=error.localizedDescription }
    }
    func willSleep() {
        guard preferences.backgroundHistory else { return }
        sleepStart=BatteryReader.read();try? healthRecorder.flush()
    }
    func didWake() {
        var wake:SleepEvent?
        if let s=sleepStart, preferences.backgroundHistory {
            let e=SleepEvent(before:s,after:BatteryReader.read());wake=e
            do { try sleepStore.append(e);sleeps=sleepStore.read() } catch { message=error.localizedDescription }
        }
        sleepStart=nil;refresh(wake:wake)
    }
    var helperInstallCommand:String { "sudo /Applications/VibeBattery.app/Contents/Resources/install-helper.sh" }
    var heatStatus:String {
        let h=preferences.heat
        if !h.enabled { return "꺼짐" }
        let record=chargeController.record
        if record.heatPaused,let hold=record.heat.holdLimit { return "복원 실패로 멈춤 · 상한이 \(hold)%로 남아 있음 (원래 \(record.heat.userLimit.map { "\($0)%" } ?? "상한 없음"))" }
        if record.heatPaused { return "멈춤 · 상한이 외부에서 바뀌었거나 적용에 실패함. 다시 켜거나 상한을 적용하면 재개" }
        if let hold=chargeController.record.heat.holdLimit { return "보류 중 · 상한을 \(hold)%로 낮춤, \(Int(h.resumeAt))°C 이하 5분 유지 시 복원" }
        switch lastHeatAction {
        case .sensorUnavailable:return "중지됨 · 배터리 온도를 읽지 못함"
        case .cannotHold(.lowCharge):return "보류 불가 · 잔량 50% 미만"
        case .cannotHold(.needsHelper):return "보류 불가 · 80% 미만으로 낮추려면 헬퍼가 필요"
        case .cannotHold(.limitUnknown):return "보류 불가 · 현재 충전 상한을 읽지 못함"
        default:return "감시 중 · \(Int(h.holdAt))°C 이상 충전 시 보류 (앱 실행 중에만)"
        }
    }
    func refreshCharge() {
        let step=chargeController.heatStep(snapshot:battery,settings:preferences.heat)
        lastHeatAction=step.action
        var failed=false;if case .failure?=step.result { failed=true }
        if let e=HeatEvent.from(action:step.action,failed:failed) { pendingHeatEvent=e }
        if case .failure(let e)?=step.result { message="과열 보류를 멈췄습니다. \(e.localizedDescription) 현재 상태: \(heatStatus)" }
        charge=chargeController.state();chargeConflicts=ChargeControllerScan.current()
        loginItem=SMAppService.mainApp.status == .enabled
    }
    func applyCharge(_ c:ChargeCommand) {
        switch chargeController.apply(c) {
        case .success(let s):
            charge=s
            message=Self.chargeMessage(c,s)
        case .failure(let e):
            message=e.localizedDescription
            if c.requiresHelper { checkHelper() }
        }
    }
    func setHeatEnabled(_ on:Bool) {
        preferences.heat.enabled=on;if on { chargeController.resumeHeat() };savePreferences();refreshCharge()
    }
    func setLoginItem(_ on:Bool) {
        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { message="로그인 시 실행 설정 실패: \(error.localizedDescription)" }
        loginItem=SMAppService.mainApp.status == .enabled
    }
    private let reader=ProcessReader()
    private var timer:Timer?
    private var ticks=0
    private let historyStore=HistoryStore(url:AppPaths.directory.appendingPathComponent("history.json"))
    private let preferencesURL=AppPaths.directory.appendingPathComponent("preferences.json")
    init() {
        if let d=try? Data(contentsOf:preferencesURL),let p=try? JSONDecoder().decode(UserPreferences.self,from:d) { preferences=p;preferences.validate() }
        sleeps=sleepStore.read()
        refresh()
        checkHelper()
        checkNotifications()
        startControlServer()
        NotificationRouter.shared.open={ [weak self] in self?.show($0) }
        // A heat hold must not outlive the app that would restore it.
        NotificationCenter.default.addObserver(forName:NSApplication.willTerminateNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.controlServer?.stop();_=self?.chargeController.releaseHold();try? self?.healthRecorder.flush() }
        }
        // Permission is usually granted in System Settings; re-check when the user comes back.
        NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkNotifications() }
        }
        let ws=NSWorkspace.shared.notificationCenter
        ws.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.willSleep() } }
        ws.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.didWake() } }
        timer=Timer.scheduledTimer(withTimeInterval:5,repeats:true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    func tick() {
        ticks+=1
        if ticks%6==0 { refresh();checkNotifications() }
        let visible=NSApp.windows.contains { $0.isVisible && !$0.isMiniaturized }
        if section=="processes" && visible { processes=reader.snapshot();sampled=true }
        if section=="sessions" && visible { sessions=AppPaths.sessions.all() }
    }
    func refresh(wake:SleepEvent?=nil) {
        do { try AppPaths.sessions.removeInactive(before:Date().addingTimeInterval(-30*86400)) } catch { message=error.localizedDescription }
        battery=BatteryReader.read()
        if preferences.backgroundHistory { do { try historyStore.append(battery);try healthRecorder.record(battery) } catch { message=error.localizedDescription } }
        history=historyStore.read();sessions=AppPaths.sessions.all()
        refreshCharge()
        checkSchedules()
        updateHealthReport()
        notify(wake:wake)
    }
    func notify(wake:SleepEvent?=nil) {
        var i=NotificationInput(now:Date(),battery:battery)
        let r=chargeController.record
        i.limit=charge;i.lastWritten=r.lastWritten;i.chargeWrites=r.writes;i.topUpRequested=r.topUpRequested
        i.heatEnabled=preferences.heat.enabled;i.heatHolding=r.heat.holdLimit != nil
        i.heatStuckLimit=r.heatPaused ? r.heat.holdLimit:nil
        i.heatSensorMissing=preferences.heat.enabled && lastHeatAction == .sensorUnavailable
        i.heatEvent=pendingHeatEvent;pendingHeatEvent=nil
        i.conflicts=chargeConflicts.map(\.name)
        let store=AppPaths.sessions
        i.sessions=sessions.map { SessionSummary(id:$0.id,command:$0.command,outcome:$0.outcome,started:$0.started,ended:$0.ended,exitCode:$0.exitCode,released:store.isReleased($0.id)) }
        i.wake=wake;i.suggestions=healthReport?.suggestions ?? [];i.week=healthReport?.week
        let o=NotificationPolicy.evaluate(i,settings:preferences.notifications,memory:notificationMemory)
        notificationMemory=o.memory
        // A failed write only risks one repeated alert; the next refresh retries.
        _=try? notificationStore.save(o.memory)
        if !o.removals.isEmpty { notifier.remove(o.removals) }
        // NSApp may not exist yet during the first refresh from init.
        let front=NSApplication.shared.isActive
        for e in o.events where !(front && e.duplicatesAppMessage) { notifier.deliver(e) }
    }
    func checkNotifications() { notifier.access { [weak self] in self?.notificationAccess=$0 } }
    func requestNotifications() { notifier.request { [weak self] in self?.notificationAccess=$0 } }
    func sendTestNotification() {
        notifier.deliver(AlertEvent(id:"test",title:"VibeBattery 테스트 알림",body:"알림이 정상적으로 표시됩니다. 누르면 설정 화면이 열립니다.",section:"settings",thread:"test"))
    }
    func openNotificationSettings() { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.notifications")!) }
    func show(_ s:String) { section=s;openMain?();NSApp.activate(ignoringOtherApps:true) }
    func savePreferences() {
        preferences.validate()
        do {
            try FileManager.default.createDirectory(at:AppPaths.directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try JSONEncoder().encode(preferences).write(to:preferencesURL,options:.atomic)
        } catch { message=error.localizedDescription }
    }
    func clearHistory() {
        do { try historyStore.delete();history=[] } catch { message=error.localizedDescription }
    }
    func clearInactiveSessions() {
        do { try AppPaths.sessions.removeInactive(before:Date());sessions=AppPaths.sessions.all() }
        catch { message=error.localizedDescription }
    }
    func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath:"/System/Applications/Utilities/Activity Monitor.app"))
    }
    func release(_ r:SessionRecord) {
        do { try AppPaths.sessions.release(r.id);sessions=AppPaths.sessions.all();message="보호 해제를 요청했습니다. 실행 중인 명령은 계속 실행됩니다." }
        catch { message=error.localizedDescription }
    }
    func terminate(_ p:ProcessSample,force:Bool) {
        do { try ProcessReader.terminate(p,force:force);message="종료를 요청했습니다. 다음 측정에서 결과를 확인할 수 있습니다." }
        catch { message=error.localizedDescription }
    }
    func openBatterySettings() {
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.battery")!)
    }
    var cliPath:String { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/vbctl").path }
    func command(for executable:String) -> String {
        var parts=[ShellQuote.quote(cliPath),"run","--hours",String(format:"%g",preferences.hours)]
        if preferences.screenOff { parts.append("--screen-off") }
        if preferences.cleanup { parts.append("--cleanup") }
        parts += ["--",executable]
        return parts.joined(separator:" ")
    }
    func copyCommand(_ executable:String) {
        NSPasteboard.general.clearContents();NSPasteboard.general.setString(command(for:executable),forType:.string)
        message="명령을 복사했습니다. iTerm2 또는 Ghostty에 붙여 넣어 시작하세요."
    }
    func copyText(_ text:String) {
        NSPasteboard.general.clearContents();NSPasteboard.general.setString(text,forType:.string)
        message="경로를 복사했습니다: \(text)"
    }
    func ownerAlive(_ r:SessionRecord) -> Bool { guard let o=r.owner else { return false };return ProcessReader.one(o.pid)?.identity==o }
    func status(_ r:SessionRecord) -> String {
        if r.ended==nil && !ownerAlive(r) { return "관리 연결 끊김" }
        if r.ended==nil && AppPaths.sessions.isReleased(r.id) { return "보호 해제 요청됨" }
        switch r.outcome {
        case .running:return r.protected ? "작업 보호 중":"실행 중"
        case .succeeded:return "완료"
        case .failed:return "실패"
        case .cancelled:return "취소"
        case .detached:return r.ended==nil ? "보호 해제 · 작업 실행 중":"보호 해제 후 종료"
        case .expired:return r.ended==nil ? "시간 만료 · 작업 실행 중":"시간 만료 후 종료"
        }
    }
}
