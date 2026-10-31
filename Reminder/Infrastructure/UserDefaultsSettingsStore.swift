import Foundation

/// 通知の設定を UserDefaults に置く
@MainActor
final class UserDefaultsSettingsStore: SettingsStore {
    private static let alertLeadMinutesKey = "alertLeadMinutes"
    private static let enabledCalendarIDsKey = "enabledCalendarIDs"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var alertLeadMinutes: Set<Int> {
        get { Set(defaults.array(forKey: Self.alertLeadMinutesKey) as? [Int] ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Self.alertLeadMinutesKey) }
    }

    var enabledCalendarIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.enabledCalendarIDsKey) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Self.enabledCalendarIDsKey) }
    }
}
