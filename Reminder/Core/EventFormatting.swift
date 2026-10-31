import Foundation

/// 予定の表示用の文字列
enum EventFormatting {
    /// 「あと45秒」「開始時刻です」「開始から3分経過」
    static func relativeDescription(start: Date, now: Date) -> String {
        let seconds = start.timeIntervalSince(now)
        if seconds > 0 {
            let remaining = Int(seconds.rounded(.up))
            return remaining < 60 ? "あと\(remaining)秒" : "あと\(Int((seconds / 60).rounded(.up)))分"
        }
        let elapsedMinutes = Int(-seconds / 60)
        return elapsedMinutes == 0 ? "開始時刻です" : "開始から\(elapsedMinutes)分経過"
    }

    /// 「9:05」
    static func time(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    /// メニューの「今日の予定」の1行。「9:05  定例（仕事）」
    static func todayMenuTitle(_ event: CalendarEvent, calendar: Calendar = .current) -> String {
        let title = "\(time(event.start, calendar: calendar))  \(event.title)"
        return event.calendarName.isEmpty ? title : "\(title)（\(event.calendarName)）"
    }

    /// 「通知するカレンダー（2/15）」。選んだ数が一目で分かるようにする
    static func calendarMenuTitle(enabled: Int, total: Int) -> String {
        total == 0 ? "通知するカレンダー" : "通知するカレンダー（\(enabled)/\(total)）"
    }

    /// 「仕事（今日 3件）」。どのカレンダーに予定が入っているか、選ぶときの目安にする
    static func calendarToggleTitle(_ title: String, todayCount: Int) -> String {
        todayCount == 0 ? title : "\(title)（今日 \(todayCount)件）"
    }

    /// 「9:05 – 10:00」
    static func timeRange(start: Date, end: Date, calendar: Calendar = .current) -> String {
        "\(time(start, calendar: calendar)) – \(time(end, calendar: calendar))"
    }
}
