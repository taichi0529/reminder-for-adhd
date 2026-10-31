import AppKit
import Observation

/// 画面に出す状態と、いつ判定し直すか (タイマー・OS からの通知) を受け持つ。
/// どの予定をいつ通知するかは ReminderService が決める。
/// バッテリーのため定期的には動かさず、次に表示が変わる時刻と OS からの通知でだけ動く
@MainActor
@Observable
final class AppModel {
    /// 通知の何秒前から App Nap を止めて、タイマーが遅れないようにするか
    private static let napGuardLead: TimeInterval = 2 * 60
    /// 変更通知を取りこぼしたときのための読み直し間隔
    private static let safetyRefreshInterval: TimeInterval = 30 * 60
    /// メニューで選べる通知のタイミング (開始の何分前か)
    static let alertLeadChoices = ReminderService.alertLeadChoices

    private(set) var access: CalendarAccess
    private(set) var todayEvents: [CalendarEvent] = []
    private(set) var calendars: [CalendarInfo] = []
    /// 選んでいないものも含めた、カレンダーごとの今日の予定の件数。メニューで選ぶときの目安
    private(set) var todayEventCounts: [String: Int] = [:]
    /// 通知するカレンダーが1つも選ばれていない
    private(set) var needsCalendarSelection = false
    private(set) var now = Date()
    /// 通知するタイミング (開始の何分前か)。空にはしない
    private(set) var alertLeadMinutes: Set<Int>
    /// 通知するカレンダー。最初は空で、メニューで選んだものだけを通知する
    private(set) var enabledCalendarIDs: Set<String>
    let audio: any AudioOutput

    @ObservationIgnored private let service: ReminderService
    @ObservationIgnored private let overlay = OverlayController()
    @ObservationIgnored private var transitionTimer: Timer?
    @ObservationIgnored private var safetyTimer: Timer?
    @ObservationIgnored private var systemObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var napActivity: NSObjectProtocol?

    init(service: ReminderService, audio: any AudioOutput) {
        self.service = service
        self.audio = audio
        access = service.access
        alertLeadMinutes = service.alertLeadMinutes
        enabledCalendarIDs = service.enabledCalendarIDs
    }

    /// アカウントごとにまとめたカレンダー
    var calendarGroups: [(account: String, calendars: [CalendarInfo])] {
        calendars.groupedByAccount()
    }

    /// 今あるカレンダーのうち、通知するものの数
    var enabledCalendarCount: Int {
        CalendarSelection.enabledCount(of: calendars.map(\.id), in: enabledCalendarIDs)
    }

    func start() async {
        service.onChange = { [weak self] in self?.refresh() }
        overlay.onAction = { [weak self] action, alert in self?.handle(action, for: alert) }
        audio.start()
        observeAudioStatus()
        observeSystemEvents()
        startSafetyTimer()
        refresh()

        if await service.requestAccessIfNeeded() {
            refresh()
        }
    }

    func requestCalendarAccess() {
        if service.access == .notDetermined {
            Task {
                _ = await service.requestAccessIfNeeded()
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
        guard service.setAlertLead(minutes, enabled: enabled) else { return }
        alertLeadMinutes = service.alertLeadMinutes
        refresh()
    }

    /// カレンダーの通知のオン・オフを切り替える
    func setCalendar(_ id: String, enabled: Bool) {
        setCalendars([id], enabled: enabled)
    }

    /// 複数のカレンダー (アカウントの全カレンダーなど) の通知をまとめて切り替える
    func setCalendars(_ ids: [String], enabled: Bool) {
        service.setCalendars(ids, enabled: enabled)
        enabledCalendarIDs = service.enabledCalendarIDs
        refresh()
    }

    /// 本物の予定を待たずに通知パネルの見た目を確かめる
    func showPreview() {
        service.showPreview(now: Date())
        refresh()
    }

    // MARK: - 判定

    private func refresh() {
        now = Date()
        let snapshot = service.snapshot(now: now)

        // 変わったときだけ書き換え、メニューの描き直しを減らす
        if snapshot.access != access { access = snapshot.access }
        if snapshot.calendars != calendars { calendars = snapshot.calendars }
        if snapshot.todayEventCounts != todayEventCounts { todayEventCounts = snapshot.todayEventCounts }
        if snapshot.todayEvents != todayEvents { todayEvents = snapshot.todayEvents }
        if snapshot.needsCalendarSelection != needsCalendarSelection {
            needsCalendarSelection = snapshot.needsCalendarSelection
        }

        overlay.update(alerts: snapshot.dueAlerts, snoozeMinutes: service.snoozeMinutes, audioStatus: audio.status)
        scheduleNextRefresh(nextTransition: snapshot.nextTransition, nextAlert: snapshot.nextAlert)
    }

    private func handle(_ action: OverlayAction, for alert: Alert) {
        let response: AlertResponse
        switch action {
        case .unmute:
            audio.unmute()
            return
        case .join: response = .join
        case .acknowledge: response = .acknowledge
        case .snooze: response = .snooze
        }
        if let url = service.respond(response, to: alert, now: Date()) {
            NSWorkspace.shared.open(url)
        }
        refresh()
    }

    // MARK: - タイマー

    /// 次に表示が変わる時刻に1回だけ起きる。通知が近いときだけ App Nap を止める
    private func scheduleNextRefresh(nextTransition: Date?, nextAlert: Date?) {
        transitionTimer?.invalidate()
        transitionTimer = nil

        let napGuardStart = nextAlert?.addingTimeInterval(-Self.napGuardLead)
        if let napGuardStart, napGuardStart <= now {
            beginNapGuard()
        } else {
            endNapGuard()
        }

        let wakeDates = [nextTransition, napGuardStart.flatMap { $0 > now ? $0 : nil }]
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
