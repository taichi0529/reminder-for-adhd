import Foundation
import Testing

struct AlertPlannerTests {
    private let planner = AlertPlanner()
    /// 5分前・1分前・開始時刻に通知する
    private let multiPlanner = AlertPlanner(config: AlertConfig(leads: [300, 60, 0]))
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(id: String = "a", start: Date? = nil, minutes: Double = 30) -> CalendarEvent {
        let start = start ?? self.start
        return CalendarEvent(id: id, title: id, start: start, end: start.addingTimeInterval(minutes * 60))
    }

    private func due(
        _ events: [CalendarEvent],
        at offset: TimeInterval,
        state: AlertState = AlertState(),
        planner: AlertPlanner? = nil
    ) -> [String] {
        (planner ?? self.planner).dueAlerts(events, now: start.addingTimeInterval(offset), state: state).map(\.id)
    }

    private func alert(_ event: CalendarEvent, at offset: TimeInterval) throws -> Alert {
        try #require(multiPlanner.currentAlert(for: event, now: start.addingTimeInterval(offset)))
    }

    // MARK: - 開始時刻だけ (既定)

    @Test func 開始前は通知しない() {
        #expect(due([event()], at: -1).isEmpty)
    }

    @Test func 開始時刻ちょうどに通知する() {
        #expect(due([event()], at: 0) == ["a#0"])
    }

    @Test func 開始から30分を過ぎたら通知しない() {
        let long = event(minutes: 120)
        #expect(due([long], at: 29 * 60) == ["a#0"])
        #expect(due([long], at: 30 * 60).isEmpty)
    }

    @Test func 終わった予定は通知しない() {
        let short = event(minutes: 10)
        #expect(due([short], at: 9 * 60) == ["a#0"])
        #expect(due([short], at: 10 * 60).isEmpty)
    }

    @Test func 長さ0の予定も開始後1分は通知する() {
        let zero = event(minutes: 0)
        #expect(due([zero], at: 59) == ["a#0"])
        #expect(due([zero], at: 60).isEmpty)
    }

    @Test func 了解した予定は通知しない() {
        var state = AlertState()
        state.markHandled(Alert(event: event(), lead: 0))
        #expect(due([event()], at: 0, state: state).isEmpty)
    }

    @Test func もう一回を押すと指定時刻まで通知しない() {
        var state = AlertState()
        state.snooze(Alert(event: event(), lead: 0), until: planner.snoozeDate(now: start))
        #expect(due([event()], at: 0, state: state).isEmpty)
        #expect(due([event()], at: 5 * 60 - 1, state: state).isEmpty)
        #expect(due([event()], at: 5 * 60, state: state) == ["a#0"])
    }

    @Test func 複数あるときは開始の早い順() {
        let later = event(id: "later", start: start.addingTimeInterval(30))
        let earlier = event(id: "earlier")
        #expect(due([later, earlier], at: 30) == ["earlier#0", "later#0"])
    }

    // MARK: - 複数のタイミング

    @Test func 各タイミングで通知が切り替わる() {
        #expect(due([event()], at: -5 * 60 - 1, planner: multiPlanner).isEmpty)
        #expect(due([event()], at: -5 * 60, planner: multiPlanner) == ["a#300"])
        #expect(due([event()], at: -61, planner: multiPlanner) == ["a#300"])
        #expect(due([event()], at: -60, planner: multiPlanner) == ["a#60"])
        #expect(due([event()], at: 0, planner: multiPlanner) == ["a#0"])
    }

    @Test func 了解してもその後のタイミングでまた通知する() throws {
        var state = AlertState()
        state.markHandled(try alert(event(), at: -5 * 60))
        #expect(due([event()], at: -2 * 60, state: state, planner: multiPlanner).isEmpty)
        #expect(due([event()], at: -60, state: state, planner: multiPlanner) == ["a#60"])
    }

    @Test func 参加したらその後のタイミングでも通知しない() {
        var state = AlertState()
        state.markFinished(event())
        #expect(due([event()], at: -60, state: state, planner: multiPlanner).isEmpty)
        #expect(due([event()], at: 0, state: state, planner: multiPlanner).isEmpty)
    }

    @Test func もう一回の途中でも次のタイミングが来たら通知する() throws {
        var state = AlertState()
        let fiveMinutesBefore = try alert(event(), at: -5 * 60)
        state.snooze(fiveMinutesBefore, until: multiPlanner.snoozeDate(now: start.addingTimeInterval(-5 * 60)))
        #expect(due([event()], at: -2 * 60, state: state, planner: multiPlanner).isEmpty)
        #expect(due([event()], at: -60, state: state, planner: multiPlanner) == ["a#60"])
    }

    @Test func 開始時刻を選ばなければ開始後も直前のタイミングの通知を出し続ける() {
        let planner = AlertPlanner(config: AlertConfig(leads: [300]))
        #expect(due([event()], at: 10 * 60, planner: planner) == ["a#300"])
    }

    @Test func タイミングが空なら通知しない() {
        let planner = AlertPlanner(config: AlertConfig(leads: []))
        #expect(due([event()], at: 0, planner: planner).isEmpty)
    }

    // MARK: - 次に起きる時刻

    @Test func 次に起きる時刻は直近の変わり目() {
        let events = [event(id: "b", start: start.addingTimeInterval(3600)), event()]
        let now = start.addingTimeInterval(-10 * 60)
        #expect(planner.nextTransition(events, now: now, state: AlertState()) == start)
        #expect(multiPlanner.nextTransition(events, now: now, state: AlertState()) == start.addingTimeInterval(-5 * 60))
        #expect(multiPlanner.nextTransition(events, now: start.addingTimeInterval(-5 * 60), state: AlertState()) == start.addingTimeInterval(-60))
    }

    @Test func 次に起きる時刻にもう一回の時刻を含める() {
        var state = AlertState()
        let snoozeUntil = start.addingTimeInterval(2 * 60)
        state.snooze(Alert(event: event(id: "x", start: start.addingTimeInterval(-3600)), lead: 0), until: snoozeUntil)
        let next = planner.nextTransition([event(minutes: 10)], now: start.addingTimeInterval(60), state: state)
        #expect(next == snoozeUntil)
    }

    @Test func 予定がなければ起きない() {
        #expect(planner.nextTransition([], now: start, state: AlertState()) == nil)
    }

    @Test func 古い記録は捨てる() {
        var state = AlertState()
        let handled = Alert(event: event(), lead: 0)
        state.markHandled(handled)
        state.snooze(Alert(event: event(id: "b"), lead: 0), until: start.addingTimeInterval(60))
        state.prune(now: start.addingTimeInterval(2 * 24 * 60 * 60))
        #expect(!state.isHandled(handled))
        #expect(state.snoozedUntil.isEmpty)
    }
}
