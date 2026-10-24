import AppIntents
import BatteryCore
import BatteryPlatform
/// Shown by Shortcuts when an action fails, with the same text the app would show.
struct ShortcutFailure: Error, CustomLocalizedStringResourceConvertible {
    let message:String
    var localizedStringResource:LocalizedStringResource { "\(message)" }
}
@MainActor private func run(_ c:ChargeCommand) throws -> some IntentResult & ProvidesDialog {
    let r=AppModel.shared.perform(c,source:.shortcut)
    guard r.ok else { throw ShortcutFailure(message:r.message) }
    return .result(dialog:"\(r.message)")
}
struct SetChargeLimitIntent: AppIntent {
    static let title:LocalizedStringResource="충전 상한 설정"
    static let description=IntentDescription("충전 상한을 50~100% 사이에서 5% 단위로 바꿉니다. 80% 미만은 충전 헬퍼가 필요합니다.")
    static let openAppWhenRun=false
    @Parameter(title:"상한",default:80,inclusiveRange:(50,100)) var percent:Int
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard ChargeCommand.setLimit(percent).isValid else { throw ShortcutFailure(message:ChargeError.invalid.localizedDescription) }
        return try run(.setLimit(percent))
    }
}
struct StartTopUpIntent: AppIntent {
    static let title:LocalizedStringResource="한 번 완충 시작"
    static let description=IntentDescription("이번 한 번만 100%까지 충전합니다. 끝나면 원래 상한으로 돌아갑니다.")
    static let openAppWhenRun=false
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog { try run(.startTopUp) }
}
struct EndTopUpIntent: AppIntent {
    static let title:LocalizedStringResource="완충 종료"
    static let description=IntentDescription("진행 중인 한 번 완충을 끝내고 원래 상한으로 돌아갑니다.")
    static let openAppWhenRun=false
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog { try run(.endTopUp) }
}
struct ClearChargeLimitIntent: AppIntent {
    static let title:LocalizedStringResource="충전 상한 끄기"
    static let description=IntentDescription("충전 상한을 끄고 100%까지 충전합니다.")
    static let openAppWhenRun=false
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog { try run(.clearLimit) }
}
struct BatteryStatusEntity: TransientAppEntity {
    static let typeDisplayRepresentation:TypeDisplayRepresentation="배터리 상태"
    @Property(title:"잔량") var percent:Int?
    @Property(title:"충전 중") var charging:Bool?
    @Property(title:"어댑터 연결") var onAC:Bool?
    @Property(title:"상한") var limit:Int?
    @Property(title:"건강도(추정)") var health:Int?
    @Property(title:"온도") var temperature:Double?
    var summary=""
    var displayRepresentation:DisplayRepresentation { DisplayRepresentation(title:"\(summary)") }
    init() {}
    init(_ s:ShortcutStatus) {
        percent=s.percent;charging=s.charging;onAC=s.onAC;limit=s.limit;health=s.health;temperature=s.temperature;summary=s.summary
    }
}
struct GetBatteryStatusIntent: AppIntent {
    static let title:LocalizedStringResource="배터리 상태 가져오기"
    static let description=IntentDescription("잔량, 충전 상태, 충전 상한, 건강도(추정), 온도를 가져옵니다.")
    static let openAppWhenRun=false
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<BatteryStatusEntity> & ProvidesDialog {
        let s=AppModel.shared.shortcutStatus()
        return .result(value:BatteryStatusEntity(s),dialog:"\(s.summary)")
    }
}
struct VibeBatteryShortcuts: AppShortcutsProvider {
    static var appShortcuts:[AppShortcut] {
        AppShortcut(intent:SetChargeLimitIntent(),phrases:["\(.applicationName) 상한 80%"],shortTitle:"충전 상한 설정",systemImageName:"battery.75percent")
        AppShortcut(intent:StartTopUpIntent(),phrases:["\(.applicationName) 한 번 완충"],shortTitle:"한 번 완충",systemImageName:"battery.100percent.bolt")
        AppShortcut(intent:GetBatteryStatusIntent(),phrases:["\(.applicationName) 배터리 상태"],shortTitle:"배터리 상태",systemImageName:"info.circle")
    }
}
