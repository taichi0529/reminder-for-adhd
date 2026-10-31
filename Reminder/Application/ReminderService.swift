import Foundation

/// 通知パネルのボタンへの応答
enum AlertResponse: Sendable {
    /// 会議に参加する。その予定の後のタイミングでも通知しない
    case join
    /// この回の通知だけ了解する
    case acknowledge
    /// 少し後にもう一回通知する
    case snooze
}

/// ある時点で画面に出すもの
struct ReminderSnapshot: Sendable {
    let access: CalendarAccess
    let calendars: [CalendarInfo]
    /// 通知の対象の予定 (遅れて出す分から24時間後まで)。開始の早い順
    let events: [CalendarEvent]
    let todayEvents: [CalendarEvent]
    /// 選んでいないものも含めた、カレンダーごとの今日の予定の件数
    let todayEventCounts: [String: Int]
    /// 今出すべき通知。開始の早い順
    let dueAlerts: [Alert]
    /// 通知するカレンダーが1つも選ばれていない (アクセスがあるときだけ判定する)
    let needsCalendarSelection: Bool
    /// 次に表示が変わりうる時刻
    let nextTransition: Date?
    /// 次の通知の時刻
    let nextAlert: Date?
}

/// 予定を読み、どの予定をいつ通知するかを決める。通知への応答と設定の変更もここで受ける。
/// タイマーや画面には依存しないので、時刻を渡して確かめられる
@MainActor
final class ReminderService {
    /// メニューで選べる通知のタイミング (開始の何分前か)
    static let alertLeadChoices = [5, 1, 0]

    private let source: CalendarSource
    private let settings: SettingsStore
    private let calendar: Calendar
    private var alertState = AlertState()
    /// テスト表示の予定。出している間は本物の通知より優先する
    private var previewEvent: CalendarEvent?

    init(source: CalendarSource, settings: SettingsStore, calendar: Calendar = .current) {
        self.source = source
        self.settings = settings
        self.calendar = calendar
    }

    /// 予定やカレンダーが外部で変わったときに呼ばれる
    var onChange: (() -> Void)? {
        get { source.onChange }
        set { source.onChange = newValue }
    }

    var access: CalendarAccess { source.access }

    /// 通知するタイミング (開始の何分前か)。空にはしない
    var alertLeadMinutes: Set<Int> {
        settings.alertLeadMinutes.isEmpty ? [0] : settings.alertLeadMinutes
    }

    /// 通知するカレンダー。最初は空で、選んだものだけを通知する
    var enabledCalendarIDs: Set<String> { settings.enabledCalendarIDs }

    var snoozeMinutes: Int { Int(planner.config.snooze / 60) }

    private var planner: AlertPlanner {
        AlertPlanner(config: AlertConfig(leads: Set(alertLeadMinutes.map { TimeInterval($0 * 60) })))
    }

    /// まだ聞いていなければカレンダーへのアクセスを求める。求めたら true
    func requestAccessIfNeeded() async -> Bool {
        guard source.access == .notDetermined else { return false }
        _ = await source.requestAccess()
        return true
    }

    // MARK: - 判定

    func snapshot(now: Date) -> ReminderSnapshot {
        let planner = planner
        let calendars = source.calendars()
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        // 遅れて出す分と、日付をまたいだ直後の予定まで含めて取る
        let events = source
            .events(
                from: min(startOfToday, now.addingTimeInterval(-planner.config.maxLateness)),
                to: max(endOfToday, now.addingTimeInterval(24 * 60 * 60)),
                calendarIDs: enabledCalendarIDs
            )
            .sorted { $0.start < $1.start }
        let todayEventCounts = CalendarSelection.eventCounts(
            source.events(from: startOfToday, to: endOfToday, calendarIDs: Set(calendars.map(\.id)))
        )

        alertState.prune(now: now)
        let dueAlerts = previewEvent.map { [Alert(event: $0, lead: 0)] }
            ?? planner.dueAlerts(events, now: now, state: alertState)

        return ReminderSnapshot(
            access: source.access,
            calendars: calendars,
            events: events,
            todayEvents: events.filter { calendar.isDate($0.start, inSameDayAs: now) },
            todayEventCounts: todayEventCounts,
            dueAlerts: dueAlerts,
            needsCalendarSelection: source.access == .granted
                && CalendarSelection.enabledCount(of: calendars.map(\.id), in: enabledCalendarIDs) == 0,
            nextTransition: planner.nextTransition(events, now: now, state: alertState),
            nextAlert: events.flatMap(planner.alertDates(of:)).filter { $0 > now }.min()
        )
    }

    // MARK: - 通知への応答

    /// 通知パネルのボタンへの応答。参加なら開く会議の URL を返す
    func respond(_ response: AlertResponse, to alert: Alert, now: Date) -> URL? {
        if alert.event.id == previewEvent?.id {
            previewEvent = nil
            return nil
        }
        switch response {
        case .join:
            alertState.markFinished(alert.event)
            return alert.event.meetingURL
        case .acknowledge:
            alertState.markHandled(alert)
        case .snooze:
            alertState.snooze(alert, until: planner.snoozeDate(now: now))
        }
        return nil
    }

    /// 本物の予定を待たずに通知パネルの見た目を確かめる
    func showPreview(now: Date) {
        previewEvent = CalendarEvent(
            id: "preview",
            title: "テスト表示：定例ミーティング",
            start: now,
            end: now.addingTimeInterval(30 * 60),
            location: "会議室A",
            notes: "https://meet.google.com/abc-defg-hij",
            calendarName: "テスト",
            calendarColor: RGBColor(red: 0.26, green: 0.52, blue: 0.96)
        )
    }

    // MARK: - 設定

    /// 通知するタイミングのオン・オフを切り替える。最後の1つは外せない。変えたら true
    @discardableResult
    func setAlertLead(_ minutes: Int, enabled: Bool) -> Bool {
        var leads = alertLeadMinutes
        if enabled {
            leads.insert(minutes)
        } else {
            leads.remove(minutes)
        }
        guard !leads.isEmpty, leads != alertLeadMinutes else { return false }
        settings.alertLeadMinutes = leads
        return true
    }

    /// カレンダー (アカウントの全カレンダーなど) の通知をまとめて切り替える
    func setCalendars(_ ids: [String], enabled: Bool) {
        settings.enabledCalendarIDs = CalendarSelection.setting(ids, enabled: enabled, in: enabledCalendarIDs)
    }
}
