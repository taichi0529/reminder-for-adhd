import Foundation

struct AlertConfig: Equatable, Sendable {
    /// 開始の何秒前に通知するか。複数指定でき、それぞれのタイミングで通知する
    var leads: Set<TimeInterval> = [0]
    /// 開始後、どこまで遅れても通知するか (スリープ明けなど)
    var maxLateness: TimeInterval = 30 * 60
    /// 「もう一回」で次に通知するまでの秒数
    var snooze: TimeInterval = 5 * 60
}

/// 予定に対する1回分の通知
struct Alert: Identifiable, Hashable, Sendable {
    let event: CalendarEvent
    /// 開始の何秒前の通知か
    let lead: TimeInterval

    var id: String { "\(event.id)#\(Int(lead))" }
}

/// ユーザーが通知に対して取った操作の記録
struct AlertState: Sendable {
    /// 対応済みの通知 ID (予定ごと対応済みなら予定 ID) と、その記録を捨ててよい時刻
    private var handled: [String: Date] = [:]
    /// 「もう一回」を押された通知 ID と、次に通知する時刻
    private(set) var snoozedUntil: [String: Date] = [:]

    func isHandled(_ alert: Alert) -> Bool {
        handled[alert.id] != nil || handled[alert.event.id] != nil
    }

    func isSnoozed(_ alert: Alert, at now: Date) -> Bool {
        guard let until = snoozedUntil[alert.id] else { return false }
        return until > now
    }

    /// この回の通知だけを対応済みにする。同じ予定の後のタイミングではまた通知する
    mutating func markHandled(_ alert: Alert) {
        handled[alert.id] = Self.retentionDate(of: alert.event)
        snoozedUntil[alert.id] = nil
    }

    /// 予定のすべての通知を対応済みにする (会議に参加したときなど)
    mutating func markFinished(_ event: CalendarEvent) {
        handled[event.id] = Self.retentionDate(of: event)
    }

    mutating func snooze(_ alert: Alert, until date: Date) {
        snoozedUntil[alert.id] = date
    }

    /// 不要になった記録を捨てる
    mutating func prune(now: Date) {
        handled = handled.filter { $0.value > now }
        snoozedUntil = snoozedUntil.filter { $0.value > now }
    }

    private static func retentionDate(of event: CalendarEvent) -> Date {
        max(event.start, event.end).addingTimeInterval(24 * 60 * 60)
    }
}

/// どの予定をいつ通知するかを決める
struct AlertPlanner: Sendable {
    var config = AlertConfig()

    /// 予定の各タイミングの通知時刻
    func alertDates(of event: CalendarEvent) -> [Date] {
        config.leads.map { event.start.addingTimeInterval(-$0) }
    }

    /// 通知を出す期間の終わり。開始からの許容遅れと予定の終了の早い方。
    /// 開始と終了が同じ予定でも、開始後1分は通知する
    func alertEnd(of event: CalendarEvent) -> Date {
        min(
            event.start.addingTimeInterval(config.maxLateness),
            max(event.end, event.start.addingTimeInterval(60))
        )
    }

    /// 今の時点で有効な通知。過ぎたタイミングのうち一番新しいもの
    func currentAlert(for event: CalendarEvent, now: Date) -> Alert? {
        guard now < alertEnd(of: event) else { return nil }
        let passedLeads = config.leads.filter { event.start.addingTimeInterval(-$0) <= now }
        return passedLeads.min().map { Alert(event: event, lead: $0) }
    }

    /// 今、出すべき通知。開始の早い順
    func dueAlerts(_ events: [CalendarEvent], now: Date, state: AlertState) -> [Alert] {
        events
            .compactMap { currentAlert(for: $0, now: now) }
            .filter { !state.isHandled($0) && !state.isSnoozed($0, at: now) }
            .sorted { $0.event.start < $1.event.start }
    }

    /// 次に表示内容が変わりうる時刻。この時刻にだけ起きればよい
    func nextTransition(_ events: [CalendarEvent], now: Date, state: AlertState) -> Date? {
        let eventDates = events.flatMap { alertDates(of: $0) + [$0.start, $0.end, alertEnd(of: $0)] }
        return (eventDates + state.snoozedUntil.values)
            .filter { $0 > now }
            .min()
    }

    func snoozeDate(now: Date) -> Date {
        now.addingTimeInterval(config.snooze)
    }
}
