import Observation

enum OverlayAction: Sendable {
    case join
    case acknowledge
    case snooze
    case unmute
}

/// パネルに表示する内容。複数ディスプレイのパネルで共有する
@MainActor
@Observable
final class OverlayContent {
    var alert: Alert?
    var otherCount = 0
    var snoozeMinutes = 5
    var audioStatus: AudioOutputMonitor.Status = .audible
    @ObservationIgnored var onAction: (OverlayAction) -> Void = { _ in }
}
