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

/// メニューバーのアイコンを押すと開くパネル。
/// 一番上に次の予定までの時間を大きく出し、その下に今日の予定と設定を並べる
struct MenuContent: View {
    let model: AppModel
    @State private var showsCalendars = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 残り時間の表示のため、パネルが開いている間だけ描き直す
            TimelineView(.periodic(from: .now, by: 15)) { timeline in
                NextEventCard(
                    event: model.todayEvents.nextUp(now: timeline.date),
                    now: timeline.date,
                    onOpen: open
                )
            }

            notices

            TodaySection(model: model, onOpen: open)

            Divider()

            AlertTimingRow(model: model)
            CalendarPicker(model: model, isExpanded: $showsCalendars)

            Divider()

            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    @ViewBuilder
    private var notices: some View {
        if model.access != .granted {
            Notice(systemImage: "lock.fill", text: "カレンダーへのアクセスが許可されていません") {
                Button("許可する") { model.requestCalendarAccess() }
            }
        }
        if model.needsCalendarSelection {
            Notice(systemImage: "calendar.badge.exclamationmark", text: "通知するカレンダーが選ばれていません") {
                Button("選ぶ") { withAnimation(.snappy) { showsCalendars = true } }
            }
        }
        switch model.audio.status {
        case .muted:
            Notice(systemImage: "speaker.slash.fill", text: "ミュート中のため、通知の音が鳴りません") {
                Button("解除する") { model.audio.unmute() }
            }
        case .volumeZero:
            Notice(systemImage: "speaker.slash.fill", text: "音量が0のため、通知の音が鳴りません") { EmptyView() }
        case .audible, .unknown:
            EmptyView()
        }
    }

    private var footer: some View {
        HStack {
            Button("テスト表示") {
                closePanel()
                model.showPreview()
            }
            Spacer()
            Text(Self.versionText)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("終了") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }

    private func open(_ event: CalendarEvent) {
        closePanel()
        model.open(event)
    }

    /// 会議やカレンダー.app を開いたら、パネルは閉じる
    private func closePanel() {
        NSApp.keyWindow?.close()
    }

    /// 「バージョン 0.4.0 (4)」
    private static var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "バージョン \(version) (\(build))"
    }
}

// MARK: - 次の予定

/// パネルの主役。通知パネルと同じ色 (始まる前は藍、始まったらオレンジ) で次の予定を出す
private struct NextEventCard: View {
    let event: CalendarEvent?
    let now: Date
    let onOpen: (CalendarEvent) -> Void

    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        if let event {
            Button { onOpen(event) } label: {
                content(event)
            }
            .buttonStyle(.plain)
            .accessibilityHint(event.meetingURL == nil ? "予定を開きます" : "会議に参加します")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("このあとの予定はありません")
                    .font(.headline)
                Text("今日はもう通知することがありません")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.quaternary.opacity(0.6), in: shape)
        }
    }

    private func content(_ event: CalendarEvent) -> some View {
        let hasStarted = event.start <= now
        return VStack(alignment: .leading, spacing: 6) {
            Text(hasStarted ? "進行中" : "次の予定")
                .font(.callout.weight(.medium))
                .opacity(0.85)
            Text(EventFormatting.countdown(to: event, now: now))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(event.title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
            HStack(spacing: 10) {
                Text(EventFormatting.timeRange(start: event.start, end: event.end))
                    .monospacedDigit()
                if !event.calendarName.isEmpty {
                    Text(event.calendarName)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if event.meetingURL != nil {
                    Label("参加する", systemImage: "video.fill")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.25), in: Capsule())
                }
            }
            .font(.callout)
            .opacity(0.9)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(gradient(hasStarted: hasStarted), in: shape)
        .contentShape(shape)
    }

    private func gradient(hasStarted: Bool) -> LinearGradient {
        let colors: [Color] = hasStarted
            ? [Color(red: 0.93, green: 0.36, blue: 0.13), Color(red: 0.80, green: 0.13, blue: 0.26)]
            : [Color(red: 0.20, green: 0.29, blue: 0.62), Color(red: 0.36, green: 0.21, blue: 0.58)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - 知らせ

/// 通知が届かない原因と、その場で直すボタン
private struct Notice<Action: View>: View {
    let systemImage: String
    let text: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            action()
                .controlSize(.small)
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - 今日の予定

private struct TodaySection: View {
    let model: AppModel
    let onOpen: (CalendarEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle("今日の予定")
            if model.todayEvents.isEmpty {
                Text(model.enabledCalendarCount == 0 ? "カレンダーを選ぶと、ここに今日の予定が並びます" : "今日の予定はありません")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(model.todayEvents) { event in
                            TodayRow(event: event, now: model.now, onOpen: onOpen)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 220)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct TodayRow: View {
    let event: CalendarEvent
    let now: Date
    let onOpen: (CalendarEvent) -> Void
    @State private var isHovered = false

    private var isPast: Bool { event.end <= now }
    private var isOngoing: Bool { event.start <= now && now < event.end }

    var body: some View {
        Button { onOpen(event) } label: {
            HStack(spacing: 8) {
                Capsule()
                    .fill(event.calendarColor.map(Color.init) ?? .secondary)
                    .frame(width: 3, height: 28)
                Text(EventFormatting.time(event.start))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.callout.weight(isOngoing ? .semibold : .regular))
                        .lineLimit(1)
                    if !event.calendarName.isEmpty {
                        Text(event.calendarName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if isOngoing {
                    Text("進行中")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered && !isPast ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 終わった予定は押せない (薄く表示する)
        .disabled(isPast)
        .opacity(isPast ? 0.45 : 1)
        .onHover { isHovered = $0 }
    }
}

// MARK: - 設定

private struct AlertTimingRow: View {
    let model: AppModel

    var body: some View {
        HStack {
            Text("通知のタイミング")
                .font(.callout)
            Spacer()
            HStack(spacing: 4) {
                ForEach(AppModel.alertLeadChoices, id: \.self) { minutes in
                    let isOn = model.alertLeadMinutes.contains(minutes)
                    Button(minutes == 0 ? "開始時刻" : "\(minutes)分前") {
                        model.setAlertLead(minutes, enabled: !isOn)
                    }
                    .buttonStyle(ChipStyle(isOn: isOn))
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }
}

/// 複数選べるタイミングの切り替え。選ばれているものは塗りつぶす
private struct ChipStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct CalendarPicker: View {
    let model: AppModel
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text("通知するカレンダー")
                    Spacer()
                    Text("\(model.enabledCalendarCount) / \(model.calendars.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .font(.callout)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                if model.calendars.isEmpty {
                    Text("Mac に同期されたカレンダーがありません")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(model.calendarGroups, id: \.account) { group in
                                CalendarGroupView(model: model, account: group.account, calendars: group.calendars)
                            }
                        }
                        .padding(10)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: 280)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

private struct CalendarGroupView: View {
    let model: AppModel
    let account: String
    let calendars: [CalendarInfo]

    var body: some View {
        let ids = calendars.map(\.id)
        let allOn = CalendarSelection.allEnabled(ids, in: model.enabledCalendarIDs)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(account)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button(allOn ? "すべてオフ" : "すべてオン") {
                    model.setCalendars(ids, enabled: !allOn)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            ForEach(calendars) { calendar in
                Toggle(isOn: Binding(
                    get: { model.enabledCalendarIDs.contains(calendar.id) },
                    set: { model.setCalendar(calendar.id, enabled: $0) }
                )) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(calendar.color.map(Color.init) ?? .secondary)
                            .frame(width: 8, height: 8)
                        Text(calendar.title)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        let count = model.todayEventCounts[calendar.id] ?? 0
                        if count > 0 {
                            Text("今日 \(count)件")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
                .toggleStyle(.checkbox)
            }
        }
    }
}

private struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private extension Color {
    init(_ color: RGBColor) {
        self.init(red: color.red, green: color.green, blue: color.blue)
    }
}
