import Foundation

enum CalendarAccess: Sendable {
    case notDetermined
    case granted
    case denied
}

/// 予定を通知できるカレンダー1つ
struct CalendarInfo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Google アカウントのメールアドレス・iCloud など
    let accountName: String
    var color: RGBColor? = nil
}

extension [CalendarInfo] {
    /// アカウントごとにまとめる。並びはそのままで、続いている同じアカウントを1つにする
    func groupedByAccount() -> [(account: String, calendars: [CalendarInfo])] {
        var groups: [(account: String, calendars: [CalendarInfo])] = []
        for calendar in self {
            let account = calendar.accountName.isEmpty ? "その他" : calendar.accountName
            if groups.last?.account == account {
                groups[groups.count - 1].calendars.append(calendar)
            } else {
                groups.append((account, [calendar]))
            }
        }
        return groups
    }
}
