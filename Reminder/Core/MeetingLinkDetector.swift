import Foundation

/// 予定の URL・場所・メモからオンライン会議の参加 URL を探す
enum MeetingLinkDetector {
    /// URL に使える ASCII 文字だけを拾う。直後に日本語が続いても URL に含めないため
    private static let urlCharacters = #"[A-Za-z0-9\-._~:/?#@!$&'()*+,;=%]+"#

    private static let services = [
        #"meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}"#,
        #"(?:[a-z0-9-]+\.)?zoom\.us/(?:j|my|w)/"# + urlCharacters,
        #"teams\.microsoft\.com/l/meetup-join/"# + urlCharacters,
        #"teams\.live\.com/meet/"# + urlCharacters,
    ]

    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:)]}>")

    /// 渡した順に探し、最初に見つかった URL を返す
    static func firstLink(in texts: [String?]) -> URL? {
        guard let regex = try? Regex("https://(?:" + services.joined(separator: "|") + ")").ignoresCase() else {
            return nil
        }
        for text in texts.compactMap({ $0 }) {
            guard let match = text.firstMatch(of: regex) else { continue }
            let link = text[match.range].trimmingCharacters(in: trailingPunctuation)
            if let url = URL(string: link) {
                return url
            }
        }
        return nil
    }
}
