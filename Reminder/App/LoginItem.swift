import Foundation
import os
import ServiceManagement

enum LoginItem {
    private static let didRegisterKey = "didRegisterLoginItem"
    private static let logger = Logger(subsystem: "jp.co.asaichi.reminder", category: "LoginItem")

    /// /Applications に置いたアプリを、初回だけログイン項目に登録する。
    /// 後でシステム設定から外された場合はその選択を尊重し、登録し直さない
    @MainActor
    static func registerOnceIfInstalled() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didRegisterKey),
              Bundle.main.bundleURL.path.hasPrefix("/Applications/")
        else { return }

        do {
            try SMAppService.mainApp.register()
            defaults.set(true, forKey: didRegisterKey)
        } catch {
            logger.error("ログイン項目に登録できませんでした: \(error.localizedDescription, privacy: .public)")
        }
    }
}
