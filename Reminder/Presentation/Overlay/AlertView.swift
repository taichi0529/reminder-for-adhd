import SwiftUI

struct AlertView: View {
    let content: OverlayContent

    var body: some View {
        if let alert = content.alert {
            // 秒のカウントダウンのため、パネルが出ている間だけ毎秒描き直す
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                AlertCard(
                    event: alert.event,
                    now: timeline.date,
                    otherCount: content.otherCount,
                    snoozeMinutes: content.snoozeMinutes,
                    audioStatus: content.audioStatus,
                    onAction: content.onAction
                )
            }
        }
    }
}

struct AlertCard: View {
    let event: CalendarEvent
    let now: Date
    var otherCount = 0
    var snoozeMinutes = 5
    var audioStatus: AudioStatus = .audible
    var onAction: (OverlayAction) -> Void = { _ in }

    private let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        GeometryReader { proxy in
            // 全画面にしても文字やボタンが大きくなりすぎないよう上限を設ける
            let unit = min(proxy.size.height, 360)
            HStack(spacing: unit * 0.1) {
                if let color = event.calendarColor {
                    Capsule()
                        .fill(Color(red: color.red, green: color.green, blue: color.blue))
                        .frame(width: max(6, unit * 0.03))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1.5))
                }
                details(unit: unit)
                Spacer(minLength: 0)
                actions(unit: unit)
                    .frame(width: min(320, max(200, proxy.size.width * 0.22)))
            }
            .padding(unit * 0.09)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
        }
        .foregroundStyle(.white)
        .background(background, in: shape)
        .overlay(shape.strokeBorder(.white.opacity(0.35), lineWidth: 2))
    }

    private var hasStarted: Bool { now >= event.start }

    private var background: LinearGradient {
        let colors: [Color] = hasStarted
            ? [Color(red: 0.93, green: 0.36, blue: 0.13), Color(red: 0.80, green: 0.13, blue: 0.26)]
            : [Color(red: 0.20, green: 0.29, blue: 0.62), Color(red: 0.36, green: 0.21, blue: 0.58)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func details(unit: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: unit * 0.035) {
            HStack(spacing: unit * 0.05) {
                Label(hasStarted ? "予定の時間です" : "もうすぐ予定です", systemImage: "alarm.fill")
                    .padding(.horizontal, unit * 0.05)
                    .padding(.vertical, unit * 0.015)
                    .background(.white.opacity(0.22), in: Capsule())
                Text(EventFormatting.relativeDescription(start: event.start, now: now))
                    .monospacedDigit()
            }
            .font(.system(size: unit * 0.09, weight: .semibold))

            Text(event.title)
                .font(.system(size: unit * 0.22, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .layoutPriority(1)

            HStack(spacing: unit * 0.06) {
                Label(EventFormatting.timeRange(start: event.start, end: event.end), systemImage: "clock")
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                }
                if !event.calendarName.isEmpty {
                    Label(event.calendarName, systemImage: "calendar")
                }
            }
            .font(.system(size: unit * 0.065, weight: .medium))
            .lineLimit(1)
            .opacity(0.9)

            if let warning = audioWarning {
                Label(warning, systemImage: "speaker.slash.fill")
                    .font(.system(size: unit * 0.06, weight: .semibold))
                    .padding(.horizontal, unit * 0.04)
                    .padding(.vertical, unit * 0.012)
                    .background(.black.opacity(0.3), in: Capsule())
            } else if otherCount > 0 {
                Text("ほかに\(otherCount)件の予定があります")
                    .font(.system(size: unit * 0.055))
                    .opacity(0.85)
            }
        }
    }

    private var audioWarning: String? {
        switch audioStatus {
        case .muted: "ミュート中のため音が鳴りません"
        case .volumeZero: "音量が0のため音が鳴りません"
        case .audible, .unknown: nil
        }
    }

    private func actions(unit: CGFloat) -> some View {
        VStack(spacing: unit * 0.04) {
            if event.meetingURL != nil {
                Button { onAction(.join) } label: {
                    Label("参加する", systemImage: "video.fill")
                }
                .buttonStyle(OverlayButtonStyle(prominent: true, unit: unit))
            }
            Button("了解") { onAction(.acknowledge) }
                .buttonStyle(OverlayButtonStyle(prominent: event.meetingURL == nil, unit: unit))
            Button("\(snoozeMinutes)分後にもう一回") { onAction(.snooze) }
                .buttonStyle(OverlayButtonStyle(prominent: false, unit: unit))
            if audioStatus == .muted {
                Button { onAction(.unmute) } label: {
                    Label("ミュート解除", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(OverlayButtonStyle(prominent: false, unit: unit))
            }
        }
    }
}

private struct OverlayButtonStyle: ButtonStyle {
    var prominent: Bool
    var unit: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: min(22, unit * 0.075), weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .padding(.vertical, unit * 0.04)
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : .white)
            .background(prominent ? Color.white : Color.white.opacity(0.2), in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
