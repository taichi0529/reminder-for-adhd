import Foundation

enum CalendarAccess: Sendable {
    case notDetermined
    case granted
    case denied
}

struct CalendarInfo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Google アカウントのメールアドレス・iCloud など
    let accountName: String
    var color: RGBColor? = nil
}

/// 予定の取得元。EventKit 以外 (Google Calendar API など) に差し替えられるようにしておく
@MainActor
protocol CalendarSource: AnyObject {
    var access: CalendarAccess { get }
    /// 予定やカレンダーが外部で変わったときに呼ばれる
    var onChange: (() -> Void)? { get set }

    func requestAccess() async -> CalendarAccess
    /// 予定のあるカレンダーの一覧。アカウント名・カレンダー名の順に並べる
    func calendars() -> [CalendarInfo]
    /// 指定したカレンダーの、期間に重なる通知対象の予定
    func events(from start: Date, to end: Date, calendarIDs: Set<String>) -> [CalendarEvent]
}
