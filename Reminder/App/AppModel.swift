import AppKit
import Observation

/// 予定の読み込み・通知の判定・タイマーをまとめる。
/// バッテリーのため定期的には動かさず、次に表示が変わる時刻と OS からの通知でだけ動く
@MainActor
@Observable
final class AppModel {
    /// 通知の何秒前から App Nap を止めて、タイマーが遅れないようにするか
    private static let napGuardLead: TimeInterval = 2 * 60
    /// 変更通知を取りこぼしたときのための読み直し間隔
    private static let safetyRefreshInterval: TimeInterval = 30 * 60
    /// メニューで選べる通知のタイミング (開始の何分前か)
    static let alertLeadChoices = [5, 1, 0]
    private static let alertLeadMinutesKey = "alertLeadMinutes"
    private static let enabledCalendarIDsKey = "enabledCalendarIDs"

    private(set) var access: CalendarAccess
    private(set) var todayEvents: [CalendarEvent] = []
    private(set) var calendars: [CalendarInfo] = []
    /// 選んでいないものも含めた、カレンダーごとの今日の予定の件数。メニューで選ぶときの目安
    private(set) var todayEventCounts: [String: Int] = [:]
    private(set) var now = Date()
    /// 通知するタイミング (開始の何分前か)。空にはしない
    private(set) var alertLeadMinutes: Set<Int>
    /// 通知するカレンダー。最初は空で、メニューで選んだものだけを通知する
    private(set) var enabledCalendarIDs: Set<String>
    let audio = AudioOutputMonitor()

    @ObservationIgnored private let source: CalendarSource
    @ObservationIgnored private let overlay = OverlayController()
    @ObservationIgnored private var alertState = AlertState()
    @ObservationIgnored private var events: [CalendarEvent] = []
    @ObservationIgnored private var previewEvent: CalendarEvent?
    @ObservationIgnored private var transitionTimer: Timer?
    @ObservationIgnored private var safetyTimer: Timer?
    @ObservationIgnored private var systemObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var napActivity: NSObjectProtocol?

    init() {
        source = EventKitCalendarSource()
        access = source.access
        let saved = Set(UserDefaults.standard.array(forKey: Self.alertLeadMinutesKey) as? [Int] ?? [])
        alertLeadMinutes = saved.isEmpty ? [0] : saved
        enabledCalendarIDs = Set(UserDefaults.standard.stringArray(forKey: Self.enabledCalendarIDsKey) ?? [])
    }

    /// 通知するカレンダーが1つも選ばれていない (カレンダーへのアクセスがあるときだけ判定する)
    var needsCalendarSelection: Bool {
        access == .granted && !calendars.contains { enabledCalendarIDs.contains($0.id) }
    }

    /// アカウントごとにまとめたカレンダー
    var calendarGroups: [(account: String, calendars: [CalendarInfo])] {
        var groups: [(account: String, calendars: [CalendarInfo])] = []
        for calendar in calendars {
            let account = calendar.accountName.isEmpty ? "その他" : calendar.accountName
            if groups.last?.account == account {
                groups[groups.count - 1].calendars.append(calendar)
            } else {
                groups.append((account, [calendar]))
            }
        }
        return groups
    }

    private var planner: AlertPlanner {
        AlertPlanner(config: AlertConfig(leads: Set(alertLeadMinutes.map { TimeInterval($0 * 60) })))
    }

    func start() async {
        source.onChange = { [weak self] in self?.refresh() }
        overlay.onAction = { [weak self] action, alert in self?.handle(action, for: alert) }
        audio.start()
        observeAudioStatus()
        observeSystemEvents()
        startSafetyTimer()
        refresh()

        if source.access == .notDetermined {
            _ = await source.requestAccess()
            refresh()
        }
    }

    func requestCalendarAccess() {
        if source.access == .notDetermined {
            Task {
                _ = await source.requestAccess()
                refresh()
            }
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 会議の URL があれば開き、なければカレンダー.app を開く
    func open(_ event: CalendarEvent) {
        if let url = event.meetingURL {
            NSWorkspace.shared.open(url)
        } else if let calendarApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: calendarApp, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// 通知するタイミングのオン・オフを切り替える。最後の1つは外せない
    func setAlertLead(_ minutes: Int, enabled: Bool) {
        var leads = alertLeadMinutes
        if enabled {
            leads.insert(minutes)
        } else {
            leads.remove(minutes)
        }
        guard !leads.isEmpty, leads != alertLeadMinutes else { return }
        alertLeadMinutes = leads
        UserDefaults.standard.set(leads.sorted(), forKey: Self.alertLeadMinutesKey)
        refresh()
    }

    /// カレンダーの通知のオン・オフを切り替える
    func setCalendar(_ id: String, enabled: Bool) {
        setCalendars([id], enabled: enabled)
    }

    /// 複数のカレンダー (アカウントの全カレンダーなど) の通知をまとめて切り替える
    func setCalendars(_ ids: [String], enabled: Bool) {
        enabledCalendarIDs = CalendarSelection.setting(ids, enabled: enabled, in: enabledCalendarIDs)
        UserDefaults.standard.set(enabledCalendarIDs.sorted(), forKey: Self.enabledCalendarIDsKey)
        refresh()
    }

    /// 今あるカレンダーのうち、通知するものの数
    var enabledCalendarCount: Int {
        CalendarSelection.enabledCount(of: calendars.map(\.id), in: enabledCalendarIDs)
    }

    /// 本物の予定を待たずに通知パネルの見た目を確かめる
    func showPreview() {
        let start = Date()
        previewEvent = CalendarEvent(
            id: "preview",
            title: "テスト表示：定例ミーティング",
            start: start,
            end: start.addingTimeInterval(30 * 60),
            location: "会議室A",
            notes: "https://meet.google.com/abc-defg-hij",
            calendarName: "テスト",
            calendarColor: RGBColor(red: 0.26, green: 0.52, blue: 0.96)
        )
        refresh()
    }

    // MARK: - 判定

    private func refresh() {
        now = Date()
        access = source.access
        let planner = planner

        let newCalendars = source.calendars()
        if newCalendars != calendars {
            calendars = newCalendars
        }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        // 遅れて出す分と、日付をまたいだ直後の予定まで含めて取る
        events = source
            .events(
                from: min(startOfToday, now.addingTimeInterval(-planner.config.maxLateness)),
                to: max(endOfToday, now.addingTimeInterval(24 * 60 * 60)),
                calendarIDs: enabledCalendarIDs
            )
            .sorted { $0.start < $1.start }

        let newCounts = CalendarSelection.eventCounts(
            source.events(from: startOfToday, to: endOfToday, calendarIDs: Set(newCalendars.map(\.id)))
        )
        if newCounts != todayEventCounts {
            todayEventCounts = newCounts
        }

        let newTodayEvents = events.filter { calendar.isDate($0.start, inSameDayAs: now) }
        if newTodayEvents != todayEvents {
            todayEvents = newTodayEvents
        }

        alertState.prune(now: now)
        let dueAlerts = previewEvent.map { [Alert(event: $0, lead: 0)] }
            ?? planner.dueAlerts(events, now: now, state: alertState)
        overlay.update(
            alerts: dueAlerts,
            snoozeMinutes: Int(planner.config.snooze / 60),
            audioStatus: audio.status
        )

        scheduleNextRefresh(planner: planner)
    }

    private func handle(_ action: OverlayAction, for alert: Alert) {
        if action == .unmute {
            audio.unmute()
            return
        }
        if alert.event.id == previewEvent?.id {
            previewEvent = nil
            refresh()
            return
        }
        switch action {
        case .join:
            if let url = alert.event.meetingURL {
                NSWorkspace.shared.open(url)
            }
            alertState.markFinished(alert.event)
        case .acknowledge:
            alertState.markHandled(alert)
        case .snooze:
            alertState.snooze(alert, until: planner.snoozeDate(now: Date()))
        case .unmute:
            break
        }
        refresh()
    }

    // MARK: - タイマー

    /// 次に表示が変わる時刻に1回だけ起きる。通知が近いときだけ App Nap を止める
    private func scheduleNextRefresh(planner: AlertPlanner) {
        transitionTimer?.invalidate()
        transitionTimer = nil

        let nextAlert = events
            .flatMap(planner.alertDates(of:))
            .filter { $0 > now }
            .min()
        let napGuardStart = nextAlert?.addingTimeInterval(-Self.napGuardLead)

        if let napGuardStart, napGuardStart <= now {
            beginNapGuard()
        } else {
            endNapGuard()
        }

        let wakeDates = [
            planner.nextTransition(events, now: now, state: alertState),
            napGuardStart.flatMap { $0 > now ? $0 : nil },
        ]
        guard let wakeDate = wakeDates.compactMap({ $0 }).min() else { return }

        let timer = Timer(fire: wakeDate, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        transitionTimer = timer
    }

    private func startSafetyTimer() {
        let timer = Timer(timeInterval: Self.safetyRefreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // 多少遅れてよいので、OS が他の処理とまとめて起こせるようにする
        timer.tolerance = 5 * 60
        RunLoop.main.add(timer, forMode: .common)
        safetyTimer = timer
    }

    private func beginNapGuard() {
        guard napActivity == nil else { return }
        napActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "予定の通知を時間どおりに出すため"
        )
    }

    private func endNapGuard() {
        guard let napActivity else { return }
        ProcessInfo.processInfo.endActivity(napActivity)
        self.napActivity = nil
    }

    // MARK: - OS からの通知

    private func observeSystemEvents() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        systemObservers.append(
            workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        )
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            systemObservers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                }
            )
        }
    }

    private func observeAudioStatus() {
        withObservationTracking {
            _ = audio.status
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                overlay.updateAudioStatus(audio.status)
                observeAudioStatus()
            }
        }
    }
}
