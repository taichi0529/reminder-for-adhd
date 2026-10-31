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

    // MARK: - 次の予定

    private func timed(_ id: String, from startMinutes: Double, to endMinutes: Double) -> CalendarEvent {
        CalendarEvent(id: id, title: id, start: start.addingTimeInterval(startMinutes * 60), end: start.addingTimeInterval(endMinutes * 60))
    }

    @Test func 次の予定はこれから始まる一番早い予定() {
        let events = [timed("later", from: 60, to: 90), timed("soon", from: 10, to: 40), timed("past", from: -60, to: -30)]
        #expect(events.nextUp(now: start)?.id == "soon")
    }

    @Test func 長い作業ブロックの途中でも次の会議を出す() {
        let events = [timed("block", from: -30, to: 300), timed("meeting", from: 120, to: 150)]
        #expect(events.nextUp(now: start)?.id == "meeting")
    }

    @Test func これからの予定がなければ進行中の予定() {
        let events = [timed("old", from: -120, to: 60), timed("recent", from: -10, to: 20), timed("done", from: -60, to: -1)]
        #expect(events.nextUp(now: start)?.id == "recent")
        #expect([timed("done", from: -60, to: -1)].nextUp(now: start) == nil)
    }

    @Test func 残り時間の書き方() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let countdown = { (minutesAhead: Double) in
            EventFormatting.countdown(to: self.timed("a", from: minutesAhead, to: minutesAhead + 30), now: self.start, calendar: calendar)
        }
        #expect(countdown(0.5) == "まもなく")
        #expect(countdown(1) == "あと1分")
        #expect(countdown(22.2) == "あと23分")
        #expect(countdown(60) == "あと1時間")
        #expect(countdown(65) == "あと1時間5分")
        // 始まっていれば終わる時刻。start は 2027-01-15 17:00 (日本時間)
        #expect(countdown(-5) == "17:25まで")
    }
}
