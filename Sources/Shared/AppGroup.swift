import Foundation

/// App Group 共享容器。小组件与主 App 通过它交换今日快照。
///
/// 真实使用的 Group ID 由构建时的 `APP_GROUP_ID` 注入到 Info.plist 的
/// `AppGroupIdentifier` 键里。免费个人开发者的 Group ID 必须以 Team ID 前缀，
/// 形如 `group.<TeamID>.com.god.fitstate`。
enum AppGroup {
    static let fallbackIdentifier = "group.com.god.fitstate"

    static let identifier: String = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        return fallbackIdentifier
    }()

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var isAvailable: Bool { containerURL != nil }
}
