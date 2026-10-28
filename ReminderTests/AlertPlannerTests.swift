import Foundation
import Testing

struct AlertPlannerTests {
    private let planner = AlertPlanner()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(id: String = "a", start: Date? = nil, minutes: Double = 30) -> CalendarEvent {
        let start = start ?? self.start
        return CalendarEvent(id: id, title: id, start: start, end: start.addingTimeInterval(minutes * 60))
    }

    private func due(_ events: [CalendarEvent], at offset: TimeInterval, state: AlertState = AlertState()) -> [String] {
        planner.dueEvents(events, now: start.addingTimeInterval(offset), state: state).map(\.id)
    }

    @Test func 開始前は通知しない() {
        #expect(due([event()], at: -1).isEmpty)
    }

    @Test func 開始時刻ちょうどに通知する() {
        #expect(due([event()], at: 0) == ["a"])
    }

    @Test func 開始前に通知する設定にもできる() {
        let early = AlertPlanner(config: AlertConfig(lead: 60))
        #expect(early.dueEvents([event()], now: start.addingTimeInterval(-61), state: AlertState()).isEmpty)
        #expect(early.dueEvents([event()], now: start.addingTimeInterval(-60), state: AlertState()).map(\.id) == ["a"])
    }

    @Test func 開始から30分を過ぎたら通知しない() {
        let long = event(minutes: 120)
        #expect(due([long], at: 29 * 60) == ["a"])
        #expect(due([long], at: 30 * 60).isEmpty)
    }

    @Test func 終わった予定は通知しない() {
        let short = event(minutes: 10)
        #expect(due([short], at: 9 * 60) == ["a"])
        #expect(due([short], at: 10 * 60).isEmpty)
    }

    @Test func 長さ0の予定も開始後1分は通知する() {
        let zero = event(minutes: 0)
        #expect(due([zero], at: 59) == ["a"])
        #expect(due([zero], at: 60).isEmpty)
    }

    @Test func 了解した予定は通知しない() {
        var state = AlertState()
        state.markHandled(event())
        #expect(due([event()], at: 0, state: state).isEmpty)
    }

    @Test func もう一回を押すと指定時刻まで通知しない() {
        var state = AlertState()
        let snoozeUntil = planner.snoozeDate(now: start)
        state.snooze(event(), until: snoozeUntil)
        #expect(due([event()], at: 0, state: state).isEmpty)
        #expect(due([event()], at: 5 * 60 - 1, state: state).isEmpty)
        #expect(due([event()], at: 5 * 60, state: state) == ["a"])
    }

    @Test func 複数あるときは開始の早い順() {
        let later = event(id: "later", start: start.addingTimeInterval(30))
        let earlier = event(id: "earlier")
        #expect(due([later, earlier], at: 30) == ["earlier", "later"])
    }

    @Test func 次に起きる時刻は直近の変わり目() {
        let events = [event(id: "b", start: start.addingTimeInterval(3600)), event()]
        let now = start.addingTimeInterval(-10 * 60)
        #expect(planner.nextTransition(events, now: now, state: AlertState()) == start)
    }

    @Test func 次に起きる時刻にもう一回の時刻を含める() {
        var state = AlertState()
        let snoozeUntil = start.addingTimeInterval(2 * 60)
        state.snooze(event(id: "x", start: start.addingTimeInterval(-3600)), until: snoozeUntil)
        let next = planner.nextTransition([event(minutes: 10)], now: start.addingTimeInterval(60), state: state)
        #expect(next == snoozeUntil)
    }

    @Test func 予定がなければ起きない() {
        #expect(planner.nextTransition([], now: start, state: AlertState()) == nil)
    }

    @Test func 古い記録は捨てる() {
        var state = AlertState()
        state.markHandled(event())
        state.snooze(event(id: "b"), until: start.addingTimeInterval(60))
        state.prune(now: start.addingTimeInterval(2 * 24 * 60 * 60))
        #expect(!state.isHandled(event()))
        #expect(state.snoozedUntil.isEmpty)
    }
}
