import Foundation

enum CalendarAccess: Sendable {
    case notDetermined
    case granted
    case denied
}

/// 予定の取得元。EventKit 以外 (Google Calendar API など) に差し替えられるようにしておく
@MainActor
protocol CalendarSource: AnyObject {
    var access: CalendarAccess { get }
    /// 予定が外部で変わったときに呼ばれる
    var onChange: (() -> Void)? { get set }

    func requestAccess() async -> CalendarAccess
    /// 期間に重なる、通知対象の予定
    func events(from start: Date, to end: Date) -> [CalendarEvent]
}
