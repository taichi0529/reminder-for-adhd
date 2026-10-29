import CoreGraphics
import EventKit

/// macOS のカレンダーに同期された予定 (Google アカウントを含む) を読む
@MainActor
final class EventKitCalendarSource: CalendarSource {
    var onChange: (() -> Void)?

    private let store = EKEventStore()
    private var changeObserver: NSObjectProtocol?

    init() {
        // 同期が終わるたびに OS から届く。定期的に見に行かずに済む
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
    }

    var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() async -> CalendarAccess {
        await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { @Sendable _, _ in
                continuation.resume()
            }
        }
        return access
    }

    func calendars() -> [CalendarInfo] {
        guard access == .granted else { return [] }
        return store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, accountName: $0.source?.title ?? "") }
            .sorted { ($0.accountName, $0.title) < ($1.accountName, $1.title) }
    }

    func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [CalendarEvent] {
        guard access == .granted else { return [] }
        let calendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        // calendars に空配列を渡すと全カレンダーが対象になってしまうので、先に抜ける
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .filter(Self.shouldNotify)
            .map(CalendarEvent.init)
    }

    /// 終日の予定・キャンセルされた予定・自分が辞退した予定は通知しない
    private static func shouldNotify(_ event: EKEvent) -> Bool {
        guard !event.isAllDay, event.status != .canceled else { return false }
        let me = event.attendees?.first { $0.isCurrentUser }
        return me?.participantStatus != .declined
    }
}

private extension CalendarEvent {
    init(_ event: EKEvent) {
        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        let title = event.title ?? ""
        self.init(
            // 繰り返し予定は全回で ID が同じなので、開始時刻を足して回ごとに分ける
            id: "\(identifier)@\(Int(event.startDate.timeIntervalSince1970))",
            title: title.isEmpty ? "(タイトルなし)" : title,
            start: event.startDate,
            end: event.endDate,
            location: event.location,
            notes: event.notes,
            url: event.url,
            calendarName: event.calendar?.title ?? "",
            calendarColor: RGBColor(event.calendar?.cgColor)
        )
    }
}

private extension RGBColor {
    init?(_ color: CGColor?) {
        guard let color,
              let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let components = color.converted(to: sRGB, intent: .defaultIntent, options: nil)?.components,
              components.count >= 3
        else { return nil }
        self.init(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
    }
}
