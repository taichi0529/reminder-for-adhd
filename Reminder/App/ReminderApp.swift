import SwiftUI

@main
struct ReminderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: appDelegate.model)
        } label: {
            MenuBarIcon(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// 組み立て役。外とつなぐ実装 (EventKit・UserDefaults・CoreAudio) を作り、画面側に渡す
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(
        service: ReminderService(source: EventKitCalendarSource(), settings: UserDefaultsSettingsStore()),
        audio: AudioOutputMonitor()
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.registerOnceIfInstalled()
        Task { await model.start() }
    }
}
