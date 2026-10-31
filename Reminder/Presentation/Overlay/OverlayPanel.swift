import AppKit
import SwiftUI

/// 画面下部に予定を出すパネル。全 Space・全画面アプリの上に出し、フォーカスは奪わない
final class OverlayPanel: NSPanel {
    init(screen: NSScreen, heightRatio: Double, content: OverlayContent) {
        let frame = Self.frame(on: screen, heightRatio: heightRatio)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        let hostingView = FirstMouseHostingView(rootView: AlertView(content: content))
        hostingView.sizingOptions = []
        contentView = hostingView
        setFrame(frame, display: false)
    }

    private static func frame(on screen: NSScreen, heightRatio: Double) -> NSRect {
        let bounds = screen.frame
        let margin: CGFloat = 20
        let height = min(bounds.height - margin * 2, max(200, bounds.height * heightRatio))
        return NSRect(x: bounds.minX + margin, y: bounds.minY + margin, width: bounds.width - margin * 2, height: height)
    }
}

/// 他のアプリを使っている最中でも、1回のクリックでボタンが押せるようにする
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
