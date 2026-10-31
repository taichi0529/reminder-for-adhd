/// 通知の設定の保存先
@MainActor
protocol SettingsStore: AnyObject {
    /// 通知するタイミング (開始の何分前か)
    var alertLeadMinutes: Set<Int> { get set }
    /// 通知するカレンダーの ID
    var enabledCalendarIDs: Set<String> { get set }
}
