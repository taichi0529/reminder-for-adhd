import SwiftUI

struct MenuBarIcon: View {
    let audio: AudioOutputMonitor

    var body: some View {
        Image(systemName: audio.status.isSilent ? "calendar.badge.exclamationmark" : "calendar.badge.clock")
    }
}

struct MenuContent: View {
    let model: AppModel

    var body: some View {
        if model.access != .granted {
            Button("カレンダーへのアクセスを許可…") { model.requestCalendarAccess() }
            Divider()
        }

        Section("今日の予定") {
            if model.todayEvents.isEmpty {
                Text("今日の予定はありません")
            }
            ForEach(model.todayEvents) { event in
                let title = "\(EventFormatting.time(event.start))  \(event.title)"
                if event.end <= model.now {
                    // 終わった予定は押せない (薄く表示される)
                    Text(title)
                } else {
                    Button(title) { model.open(event) }
                }
            }
        }

        Divider()

        switch model.audio.status {
        case .muted:
            Button("ミュート中です（解除する）") { model.audio.unmute() }
        case .volumeZero:
            Text("音量が0です")
        case .audible, .unknown:
            EmptyView()
        }
        Button("テスト表示") { model.showPreview() }

        Divider()

        Button("終了") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
