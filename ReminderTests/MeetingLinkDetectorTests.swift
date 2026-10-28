import Foundation
import Testing

struct MeetingLinkDetectorTests {
    @Test func メモからGoogleMeetを見つける() {
        let notes = "Google Meet に参加: https://meet.google.com/abc-defg-hij\n電話で参加: ..."
        #expect(MeetingLinkDetector.firstLink(in: [nil, nil, notes])?.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test func Zoomはパスワード付きのまま取る() {
        let location = "https://us02web.zoom.us/j/1234567890?pwd=abcDEF123"
        #expect(MeetingLinkDetector.firstLink(in: [location])?.absoluteString == location)
    }

    @Test func Teamsを見つける() {
        let notes = "<https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d>"
        #expect(MeetingLinkDetector.firstLink(in: [notes])?.host() == "teams.microsoft.com")
    }

    @Test func 直後の日本語や句読点は含めない() {
        #expect(MeetingLinkDetector.firstLink(in: ["https://zoom.us/j/123に参加。"])?.absoluteString == "https://zoom.us/j/123")
        #expect(MeetingLinkDetector.firstLink(in: ["(https://zoom.us/j/123)."])?.absoluteString == "https://zoom.us/j/123")
    }

    @Test func 先に渡したものを優先する() {
        let url = "https://meet.google.com/aaa-bbbb-ccc"
        let notes = "https://zoom.us/j/999"
        #expect(MeetingLinkDetector.firstLink(in: [url, notes])?.absoluteString == url)
    }

    @Test func 会議以外のURLは無視する() {
        #expect(MeetingLinkDetector.firstLink(in: ["https://example.com/meeting", nil]) == nil)
    }
}
