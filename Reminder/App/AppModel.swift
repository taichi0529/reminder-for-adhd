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

    private(set) var access: CalendarAccess
    private(set) var todayEvents: [CalendarEvent] = []
    private(set) var now = Date()
    let audio = AudioOutputMonitor()

    @ObservationIgnored private let source: CalendarSource
    @ObservationIgnored private let overlay = OverlayController()
    @ObservationIgnored private let planner = AlertPlanner()
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
    }

    func start() async {
        source.onChange = { [weak self] in self?.refresh() }
        overlay.onAction = { [weak self] action, event in self?.handle(action, for: event) }
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

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        // 遅れて出す分と、日付をまたいだ直後の予定まで含めて取る
        events = source
            .events(
                from: min(startOfToday, now.addingTimeInterval(-planner.config.maxLateness)),
                to: max(endOfToday, now.addingTimeInterval(24 * 60 * 60))
            )
            .sorted { $0.start < $1.start }

        let newTodayEvents = events.filter { calendar.isDate($0.start, inSameDayAs: now) }
        if newTodayEvents != todayEvents {
            todayEvents = newTodayEvents
        }

        alertState.prune(now: now)
        let dueEvents = previewEvent.map { [$0] } ?? planner.dueEvents(events, now: now, state: alertState)
        overlay.update(
            events: dueEvents,
            snoozeMinutes: Int(planner.config.snooze / 60),
            audioStatus: audio.status
        )

        scheduleNextRefresh()
    }

    private func handle(_ action: OverlayAction, for event: CalendarEvent) {
        if action == .unmute {
            audio.unmute()
            return
        }
        if event.id == previewEvent?.id {
            previewEvent = nil
            refresh()
            return
        }
        switch action {
        case .join:
            if let url = event.meetingURL {
                NSWorkspace.shared.open(url)
            }
            alertState.markHandled(event)
        case .acknowledge:
            alertState.markHandled(event)
        case .snooze:
            alertState.snooze(event, until: planner.snoozeDate(now: Date()))
        case .unmute:
            break
        }
        refresh()
    }

    // MARK: - タイマー

    /// 次に表示が変わる時刻に1回だけ起きる。通知が近いときだけ App Nap を止める
    private func scheduleNextRefresh() {
        transitionTimer?.invalidate()
        transitionTimer = nil

        let nextAlert = events
            .map(planner.alertStart(of:))
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
