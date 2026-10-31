import Foundation

/// カレンダーの予定1件。EventKit に依存しない形で持つ
struct CalendarEvent: Identifiable, Hashable, Sendable {
    /// 繰り返し予定でも回ごとに一意になる ID
    let id: String
    let title: String
    let start: Date
    let end: Date
    let location: String?
    let notes: String?
    let url: URL?
    /// 予定が入っているカレンダーの ID (CalendarInfo.id)
    let calendarID: String
    let calendarName: String
    let calendarColor: RGBColor?
    /// Meet・Zoom・Teams の参加 URL
    let meetingURL: URL?

    init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        location: String? = nil,
        notes: String? = nil,
        url: URL? = nil,
        calendarID: String = "",
        calendarName: String = "",
        calendarColor: RGBColor? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.notes = notes
        self.url = url
        self.calendarID = calendarID
        self.calendarName = calendarName
        self.calendarColor = calendarColor
        self.meetingURL = MeetingLinkDetector.firstLink(in: [url?.absoluteString, location, notes])
    }
}

struct RGBColor: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
}
