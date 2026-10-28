import AppKit

/// 通知パネルの表示・非表示と音を管理する
@MainActor
final class OverlayController {
    /// 画面の高さに対するパネルの高さ
    static let heightRatio = 0.25
    static let soundName = "Glass"

    var onAction: ((OverlayAction, CalendarEvent) -> Void)?

    private let content = OverlayContent()
    private var panels: [OverlayPanel] = []
    private var screenObserver: NSObjectProtocol?

    init() {
        content.onAction = { [weak self] action in
            guard let self, let event = content.event else { return }
            onAction?(action, event)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.panels.isEmpty else { return }
                self.showPanels()
            }
        }
    }

    var isVisible: Bool { !panels.isEmpty }

    /// 先頭の予定を出す。空なら隠す
    func update(events: [CalendarEvent], snoozeMinutes: Int, audioStatus: AudioOutputMonitor.Status) {
        guard let event = events.first else {
            hide()
            return
        }
        let isNewEvent = event.id != content.event?.id
        content.event = event
        content.otherCount = events.count - 1
        content.snoozeMinutes = snoozeMinutes
        content.audioStatus = audioStatus

        if panels.isEmpty {
            showPanels()
        }
        if isNewEvent {
            NSSound(named: Self.soundName)?.play()
        }
    }

    func updateAudioStatus(_ status: AudioOutputMonitor.Status) {
        content.audioStatus = status
    }

    private func showPanels() {
        panels.forEach { $0.orderOut(nil) }
        panels = NSScreen.screens.map { screen in
            let panel = OverlayPanel(screen: screen, heightRatio: Self.heightRatio, content: content)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 1
            }
            return panel
        }
    }

    private func hide() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
        content.event = nil
    }
}
