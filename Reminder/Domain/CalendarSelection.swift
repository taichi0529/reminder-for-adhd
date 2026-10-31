import Foundation

/// 通知するカレンダーの選択。メニューでのまとめてオン・オフと、表示用の数
enum CalendarSelection {
    /// カレンダー ID ごとの予定の件数
    static func eventCounts(_ events: [CalendarEvent]) -> [String: Int] {
        events.reduce(into: [:]) { counts, event in counts[event.calendarID, default: 0] += 1 }
    }

    /// 今あるカレンダーのうち選ばれている数。もう無いカレンダーの ID は数えない
    static func enabledCount(of calendarIDs: [String], in enabled: Set<String>) -> Int {
        calendarIDs.filter(enabled.contains).count
    }

    /// すべて選ばれているか。カレンダーが1つもなければ false
    static func allEnabled(_ calendarIDs: [String], in enabled: Set<String>) -> Bool {
        !calendarIDs.isEmpty && calendarIDs.allSatisfy(enabled.contains)
    }

    /// まとめてオン・オフした後の選択。他のカレンダーの選択はそのまま
    static func setting(_ calendarIDs: [String], enabled: Bool, in current: Set<String>) -> Set<String> {
        enabled ? current.union(calendarIDs) : current.subtracting(calendarIDs)
    }
}
