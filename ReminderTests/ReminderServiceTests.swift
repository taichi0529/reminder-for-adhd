import Foundation
import Testing

/// 決めたカレンダーと予定を返す取得元
@MainActor
private final class FakeCalendarSource: CalendarSource {
    var access: CalendarAccess = .granted
    var onChange: (() -> Void)?
    var calendarList: [CalendarInfo] = []
    var allEvents: [CalendarEvent] = []
    private(set) var accessRequests = 0

    func requestAccess() async -> CalendarAccess {
        accessRequests += 1
        access = .granted
        return access
    }

    func calendars() -> [CalendarInfo] { calendarList }

    func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [CalendarEvent] {
        allEvents.filter { calendarIDs.contains($0.calendarID) && $0.end > start && $0.start < end }
    }
}

@MainActor
private final class InMemorySettingsStore: SettingsStore {
    var alertLeadMinutes: Set<Int> = []
    var enabledCalendarIDs: Set<String> = []
}

@MainActor
struct ReminderServiceTests {
    private let source = FakeCalendarSource()
    private let settings = InMemorySettingsStore()
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()
    /// 2027-01-15 17:00 (日本時間)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var service: ReminderService {
        ReminderService(source: source, settings: settings, calendar: calendar)
    }

    private func event(_ id: String, calendar: String = "work", in minutes: Double, url: String? = nil) -> CalendarEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return CalendarEvent(
            id: id,
            title: id,
            start: start,
            end: start.addingTimeInterval(30 * 60),
            url: url.flatMap(URL.init(string:)),
            calendarID: calendar
        )
    }

    init() {
        source.calendarList = [
            CalendarInfo(id: "work", title: "仕事", accountName: "me@example.com"),
            CalendarInfo(id: "home", title: "家", accountName: "me@example.com"),
        ]
    }

    // MARK: - 判定

    @Test func 選んだカレンダーの予定だけを通知の対象にする() {
        settings.enabledCalendarIDs = ["work"]
        source.allEvents = [event("会議", calendar: "work", in: 10), event("買い物", calendar: "home", in: 20)]
        let snapshot = service.snapshot(now: now)
        #expect(snapshot.events.map(\.id) == ["会議"])
        #expect(snapshot.todayEvents.map(\.id) == ["会議"])
    }

    @Test func 今日の件数は選んでいないカレンダーも数える() {
        settings.enabledCalendarIDs = ["work"]
        source.allEvents = [event("会議", calendar: "work", in: 10), event("買い物", calendar: "home", in: 20)]
        #expect(service.snapshot(now: now).todayEventCounts == ["work": 1, "home": 1])
    }

    @Test func 開始時刻になったら通知する() {
        settings.enabledCalendarIDs = ["work"]
        source.allEvents = [event("会議", in: 0)]
        let service = service
        #expect(service.snapshot(now: now.addingTimeInterval(-1)).dueAlerts.isEmpty)
        #expect(service.snapshot(now: now).dueAlerts.map(\.event.id) == ["会議"])
    }

    @Test func 次に起きる時刻と次の通知の時刻() {
        settings.enabledCalendarIDs = ["work"]
        settings.alertLeadMinutes = [5, 0]
        source.allEvents = [event("会議", in: 10)]
        let snapshot = service.snapshot(now: now)
        #expect(snapshot.nextAlert == now.addingTimeInterval(5 * 60))
        #expect(snapshot.nextTransition == now.addingTimeInterval(5 * 60))
    }

    @Test func カレンダーを1つも選んでいなければ知らせる() {
        #expect(service.snapshot(now: now).needsCalendarSelection)
        settings.enabledCalendarIDs = ["work"]
        #expect(!service.snapshot(now: now).needsCalendarSelection)
    }

    @Test func もう無いカレンダーだけが選ばれていても選んでいない扱い() {
        settings.enabledCalendarIDs = ["deleted"]
        #expect(service.snapshot(now: now).needsCalendarSelection)
    }

    @Test func アクセスがないときはカレンダーの選択を求めない() {
        source.access = .denied
        #expect(!service.snapshot(now: now).needsCalendarSelection)
    }

    // MARK: - 通知への応答

    @Test func 了解したら通知を消す() throws {
        settings.enabledCalendarIDs = ["work"]
        source.allEvents = [event("会議", in: 0)]
        let service = service
        let alert = try #require(service.snapshot(now: now).dueAlerts.first)
        #expect(service.respond(.acknowledge, to: alert, now: now) == nil)
        #expect(service.snapshot(now: now).dueAlerts.isEmpty)
    }

    @Test func もう一回を押すと5分後にまた通知する() throws {
        settings.enabledCalendarIDs = ["work"]
        source.allEvents = [event("会議", in: 0)]
        let service = service
        let alert = try #require(service.snapshot(now: now).dueAlerts.first)
        _ = service.respond(.snooze, to: alert, now: now)
        #expect(service.snapshot(now: now.addingTimeInterval(4 * 60)).dueAlerts.isEmpty)
        #expect(service.snapshot(now: now.addingTimeInterval(5 * 60)).dueAlerts.map(\.event.id) == ["会議"])
    }

    @Test func 参加したら会議のURLを返し後のタイミングでも通知しない() throws {
        settings.enabledCalendarIDs = ["work"]
        settings.alertLeadMinutes = [1, 0]
        source.allEvents = [event("会議", in: 1, url: "https://meet.google.com/abc-defg-hij")]
        let service = service
        let alert = try #require(service.snapshot(now: now).dueAlerts.first)
        #expect(service.respond(.join, to: alert, now: now)?.host() == "meet.google.com")
        #expect(service.snapshot(now: now.addingTimeInterval(60)).dueAlerts.isEmpty)
    }

    @Test func テスト表示は本物の通知より優先し応答したら消える() throws {
        settings.enabledCalendarIDs = ["work"]
        source.allEvents = [event("会議", in: 0)]
        let service = service
        service.showPreview(now: now)
        let preview = try #require(service.snapshot(now: now).dueAlerts.first)
        #expect(preview.event.id == "preview")
        #expect(service.respond(.join, to: preview, now: now) == nil)
        #expect(service.snapshot(now: now).dueAlerts.map(\.event.id) == ["会議"])
    }

    // MARK: - 設定

    @Test func 保存されたタイミングが空なら開始時刻だけ() {
        #expect(service.alertLeadMinutes == [0])
    }

    @Test func タイミングを変えたら保存する() {
        let service = service
        #expect(service.setAlertLead(5, enabled: true))
        #expect(settings.alertLeadMinutes == [5, 0])
        #expect(service.setAlertLead(0, enabled: false))
        #expect(settings.alertLeadMinutes == [5])
    }

    @Test func 最後のタイミングは外せない() {
        settings.alertLeadMinutes = [1]
        let service = service
        #expect(!service.setAlertLead(1, enabled: false))
        #expect(settings.alertLeadMinutes == [1])
    }

    @Test func カレンダーをまとめて切り替えて保存する() {
        let service = service
        service.setCalendars(["work", "home"], enabled: true)
        #expect(settings.enabledCalendarIDs == ["work", "home"])
        service.setCalendars(["home"], enabled: false)
        #expect(settings.enabledCalendarIDs == ["work"])
    }

    @Test func アクセスはまだ聞いていないときだけ求める() async {
        source.access = .notDetermined
        let service = service
        #expect(await service.requestAccessIfNeeded())
        #expect(await !service.requestAccessIfNeeded())
        #expect(source.accessRequests == 1)
    }

    // MARK: - カレンダーのまとめ方

    @Test func アカウントごとにまとめる() {
        let calendars = [
            CalendarInfo(id: "1", title: "仕事", accountName: "a@example.com"),
            CalendarInfo(id: "2", title: "家", accountName: "a@example.com"),
            CalendarInfo(id: "3", title: "ローカル", accountName: ""),
        ]
        let groups = calendars.groupedByAccount()
        #expect(groups.map(\.account) == ["a@example.com", "その他"])
        #expect(groups.map { $0.calendars.map(\.id) } == [["1", "2"], ["3"]])
    }
}
