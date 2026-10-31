import Foundation
import Testing

struct CalendarSelectionTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ id: String, calendar: String) -> CalendarEvent {
        CalendarEvent(id: id, title: id, start: start, end: start.addingTimeInterval(1800), calendarID: calendar)
    }

    @Test func カレンダーごとに予定を数える() {
        let events = [event("a", calendar: "work"), event("b", calendar: "work"), event("c", calendar: "home")]
        #expect(CalendarSelection.eventCounts(events) == ["work": 2, "home": 1])
        #expect(CalendarSelection.eventCounts([]).isEmpty)
    }

    @Test func 選んだ数は今あるカレンダーだけ数える() {
        // "gone" は消えたカレンダー。保存された選択に残っていても数えない
        let enabled: Set = ["work", "gone"]
        #expect(CalendarSelection.enabledCount(of: ["work", "home"], in: enabled) == 1)
        #expect(CalendarSelection.enabledCount(of: [], in: enabled) == 0)
    }

    @Test func すべて選ばれているか() {
        #expect(CalendarSelection.allEnabled(["work", "home"], in: ["work", "home", "other"]))
        #expect(!CalendarSelection.allEnabled(["work", "home"], in: ["work"]))
        #expect(!CalendarSelection.allEnabled([], in: ["work"]))
    }

    @Test func まとめてオンにしても他の選択はそのまま() {
        let result = CalendarSelection.setting(["a1", "a2"], enabled: true, in: ["b1", "a1"])
        #expect(result == ["a1", "a2", "b1"])
    }

    @Test func まとめてオフにしても他の選択はそのまま() {
        let result = CalendarSelection.setting(["a1", "a2"], enabled: false, in: ["a1", "a2", "b1"])
        #expect(result == ["b1"])
    }

    // MARK: - メニューの文字列

    @Test func 見出しに選んだ数を出す() {
        #expect(EventFormatting.calendarMenuTitle(enabled: 2, total: 15) == "通知するカレンダー（2/15）")
        #expect(EventFormatting.calendarMenuTitle(enabled: 0, total: 0) == "通知するカレンダー")
    }

    @Test func 今日の予定があるカレンダーは件数を出す() {
        #expect(EventFormatting.calendarToggleTitle("仕事", todayCount: 3) == "仕事（今日 3件）")
        #expect(EventFormatting.calendarToggleTitle("仕事", todayCount: 0) == "仕事")
    }

    @Test func 今日の予定にカレンダー名を出す() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 9, minute: 5)))
        let withCalendar = CalendarEvent(id: "a", title: "定例", start: date, end: date, calendarName: "仕事")
        let withoutCalendar = CalendarEvent(id: "b", title: "定例", start: date, end: date)
        #expect(EventFormatting.todayMenuTitle(withCalendar, calendar: calendar) == "9:05  定例（仕事）")
        #expect(EventFormatting.todayMenuTitle(withoutCalendar, calendar: calendar) == "9:05  定例")
    }
}
