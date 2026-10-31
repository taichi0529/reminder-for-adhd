import AppKit

/// 通知パネルの表示・非表示と音を管理する
@MainActor
final class OverlayController {
    /// 画面の高さに対するパネルの高さ
    static let heightRatio = 0.25
    static let soundName = "Glass"

    var onAction: ((OverlayAction, Alert) -> Void)?

    private let content = OverlayContent()
    private var panels: [OverlayPanel] = []
    private var screenObserver: NSObjectProtocol?

    init() {
        content.onAction = { [weak self] action in
            guard let self, let alert = content.alert else { return }
            onAction?(action, alert)
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

    /// 先頭の通知を出す。空なら隠す
    func update(alerts: [Alert], snoozeMinutes: Int, audioStatus: AudioStatus) {
        guard let alert = alerts.first else {
            hide()
            return
        }
        // 同じ予定でもタイミングが変われば (5分前 → 1分前など) 鳴らし直す
        let isNewAlert = alert.id != content.alert?.id
        content.alert = alert
        content.otherCount = alerts.count - 1
        content.snoozeMinutes = snoozeMinutes
        content.audioStatus = audioStatus

        if panels.isEmpty {
            showPanels()
        }
        if isNewAlert {
            NSSound(named: Self.soundName)?.play()
        }
    }

    func updateAudioStatus(_ status: AudioStatus) {
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
        content.alert = nil
    }
}
