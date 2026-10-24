import Testing
import Foundation
@testable import BatteryCore

struct ShortcutStatusTests {
    @Test func statusMapsSnapshot() {
        var b=BatterySnapshot();b.percent=82;b.charging=true;b.onAC=true;b.health=88;b.temperature=31.54
        let s=ShortcutStatus.make(b,limit:ChargeLimitState(supported:true,enabled:true,limit:70))
        #expect(s==ShortcutStatus(percent:82,charging:true,onAC:true,limit:70,health:88,temperature:31.54))
        #expect(s.summary=="배터리 82% · 충전 중 · 상한 70% · 건강도 88% · 31.5°C")
    }
    @Test func limitOffIsNil() {
        var b=BatterySnapshot();b.percent=60;b.onAC=true
        let s=ShortcutStatus.make(b,limit:ChargeLimitState(supported:true,enabled:false,limit:100))
        #expect(s.limit==nil)
        #expect(s.summary=="배터리 60% · 충전 안 함 · 상한 없음")
    }
    @Test func statusWithoutBattery() {
        let s=ShortcutStatus.make(BatterySnapshot(),limit:ChargeLimitState())
        #expect(s.percent==nil && s.limit==nil && s.health==nil && s.temperature==nil)
        #expect(s.summary=="배터리 —% · 배터리 사용 중 · 상한 없음")
    }
}
