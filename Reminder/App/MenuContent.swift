import SwiftUI

struct MenuBarIcon: View {
    let model: AppModel

    /// 音が聞こえない、または通知するカレンダーが選ばれていないときは目立たせる
    private var needsAttention: Bool {
        model.audio.status.isSilent || model.needsCalendarSelection
    }

    var body: some View {
        Image(systemName: needsAttention ? "calendar.badge.exclamationmark" : "calendar.badge.clock")
    }
}

struct MenuContent: View {
    let model: AppModel

    var body: some View {
        if model.access != .granted {
            Button("カレンダーへのアクセスを許可…") { model.requestCalendarAccess() }
            Divider()
        }
        if model.needsCalendarSelection {
            Text("⚠️ 通知するカレンダーを選んでください")
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

        Section("通知するタイミング") {
            ForEach(AppModel.alertLeadChoices, id: \.self) { minutes in
                Toggle(minutes == 0 ? "開始時刻" : "\(minutes)分前", isOn: Binding(
                    get: { model.alertLeadMinutes.contains(minutes) },
                    set: { model.setAlertLead(minutes, enabled: $0) }
                ))
            }
        }

        Menu("通知するカレンダー") {
            if model.calendars.isEmpty {
                Text("カレンダーがありません")
            }
            ForEach(model.calendarGroups, id: \.account) { group in
                Section(group.account) {
                    ForEach(group.calendars) { calendar in
                        Toggle(calendar.title, isOn: Binding(
                            get: { model.enabledCalendarIDs.contains(calendar.id) },
                            set: { model.setCalendar(calendar.id, enabled: $0) }
                        ))
                    }
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

        Text(Self.versionText)
        Button("終了") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// 「バージョン 0.3.0 (3)」
    private static var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "バージョン \(version) (\(build))"
    }
}
