import Foundation
/// What the Shortcuts "배터리 상태 가져오기" action returns.
public struct ShortcutStatus: Equatable, Sendable {
    public var percent:Int?;public var charging:Bool;public var onAC:Bool
    /// nil when the limit is off or unknown.
    public var limit:Int?
    public var health:Int?;public var temperature:Double?
    public init(percent:Int?,charging:Bool,onAC:Bool,limit:Int?,health:Int?,temperature:Double?) {
        self.percent=percent;self.charging=charging;self.onAC=onAC;self.limit=limit;self.health=health;self.temperature=temperature
    }
    public static func make(_ b:BatterySnapshot,limit:ChargeLimitState) -> ShortcutStatus {
        ShortcutStatus(percent:b.percent,charging:b.charging,onAC:b.onAC,limit:limit.enabled==true ? limit.limit:nil,health:b.health,temperature:b.temperature)
    }
    /// "배터리 82% · 충전 중 · 상한 70% · 건강도 88% · 31.5°C"
    public var summary:String {
        var parts=["배터리 \(percent.map(String.init) ?? "—")%",charging ? "충전 중":(onAC ? "충전 안 함":"배터리 사용 중"),limit.map { "상한 \($0)%" } ?? "상한 없음"]
        if let health { parts.append("건강도 \(health)%") }
        if let temperature { parts.append(String(format:"%.1f°C",temperature)) }
        return parts.joined(separator:" · ")
    }
}
