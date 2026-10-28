import Foundation

struct AlertConfig: Equatable, Sendable {
    /// 開始の何秒前に通知するか
    var lead: TimeInterval = 0
    /// 開始後、どこまで遅れても通知するか (スリープ明けなど)
    var maxLateness: TimeInterval = 30 * 60
    /// 「もう一回」で次に通知するまでの秒数
    var snooze: TimeInterval = 5 * 60
}

/// ユーザーが通知に対して取った操作の記録
struct AlertState: Sendable {
    /// 対応済みの予定 ID と、その記録を捨ててよい時刻
    private var handled: [String: Date] = [:]
    /// 「もう一回」を押された予定 ID と、次に通知する時刻
    private(set) var snoozedUntil: [String: Date] = [:]

    func isHandled(_ event: CalendarEvent) -> Bool {
        handled[event.id] != nil
    }

    func isSnoozed(_ event: CalendarEvent, at now: Date) -> Bool {
        guard let until = snoozedUntil[event.id] else { return false }
        return until > now
    }

    mutating func markHandled(_ event: CalendarEvent) {
        handled[event.id] = max(event.start, event.end).addingTimeInterval(24 * 60 * 60)
        snoozedUntil[event.id] = nil
    }

    mutating func snooze(_ event: CalendarEvent, until date: Date) {
        snoozedUntil[event.id] = date
    }

    /// 不要になった記録を捨てる
    mutating func prune(now: Date) {
        handled = handled.filter { $0.value > now }
        snoozedUntil = snoozedUntil.filter { $0.value > now }
    }
}

/// どの予定をいつ通知するかを決める
struct AlertPlanner: Sendable {
    var config = AlertConfig()

    /// 通知を出す期間の始まり
    func alertStart(of event: CalendarEvent) -> Date {
        event.start.addingTimeInterval(-config.lead)
    }

    /// 通知を出す期間の終わり。開始からの許容遅れと予定の終了の早い方。
    /// 開始と終了が同じ予定でも、開始後1分は通知する
    func alertEnd(of event: CalendarEvent) -> Date {
        min(
            event.start.addingTimeInterval(config.maxLateness),
            max(event.end, event.start.addingTimeInterval(60))
        )
    }

    /// 今、通知を出すべき予定。開始の早い順
    func dueEvents(_ events: [CalendarEvent], now: Date, state: AlertState) -> [CalendarEvent] {
        events
            .filter { event in
                alertStart(of: event) <= now
                    && now < alertEnd(of: event)
                    && !state.isHandled(event)
                    && !state.isSnoozed(event, at: now)
            }
            .sorted { $0.start < $1.start }
    }

    /// 次に表示内容が変わりうる時刻。この時刻にだけ起きればよい
    func nextTransition(_ events: [CalendarEvent], now: Date, state: AlertState) -> Date? {
        let eventDates = events.flatMap { [alertStart(of: $0), $0.start, $0.end, alertEnd(of: $0)] }
        return (eventDates + state.snoozedUntil.values)
            .filter { $0 > now }
            .min()
    }

    func snoozeDate(now: Date) -> Date {
        now.addingTimeInterval(config.snooze)
    }
}
