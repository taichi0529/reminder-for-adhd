import Foundation
import Testing

struct EventFormattingTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func relative(_ offset: TimeInterval) -> String {
        EventFormatting.relativeDescription(start: start, now: start.addingTimeInterval(offset))
    }

    @Test func 開始前は残り時間() {
        #expect(relative(-90) == "あと2分")
        #expect(relative(-60) == "あと1分")
        #expect(relative(-59) == "あと59秒")
        #expect(relative(-0.2) == "あと1秒")
    }

    @Test func 開始後は経過時間() {
        #expect(relative(0) == "開始時刻です")
        #expect(relative(59) == "開始時刻です")
        #expect(relative(60) == "開始から1分経過")
        #expect(relative(25 * 60 + 30) == "開始から25分経過")
    }

    @Test func 時刻の範囲() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 9, minute: 5)))
        let range = EventFormatting.timeRange(start: morning, end: morning.addingTimeInterval(55 * 60), calendar: calendar)
        #expect(range == "9:05 – 10:00")
    }
}
