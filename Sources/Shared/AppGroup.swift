import Foundation

/// App Group 共享容器。小组件与主 App 通过它交换今日快照。
///
/// 侧载场景有个坑：签名工具（Sideloadly，以及 Xcode 的免费个人团队）会把
/// bundle id 改写成 `<原 id>.<TeamID>`，同时在开发者门户里建出来的 App Group
/// 形如 `group.<TeamID>.com.god.fitstate`，和我们工程里写的 `group.com.god.fitstate`
/// 并不是同一个东西。直接拿配置值去查容器必然落空。
///
/// 所以这里改成运行时自适应：先从自己的 bundle id 里认出 Team ID，拼出
/// `group.<TeamID>.<后缀>` 去试；试不通再退回构建期配置的值。
/// `containerURL(forSecurityApplicationGroupIdentifier:)` 只对签名文件里
/// 真正授权的组有响应，所以多试几个候选是安全的。
enum AppGroup {
    static let fallbackIdentifier = "group.com.god.fitstate"

    /// 构建期由 Info.plist 的 AppGroupIdentifier 注入。
    static let configuredIdentifier: String = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.contains("$(") {
                return trimmed
            }
        }
        return fallbackIdentifier
    }()

    /// bundle id 里 10 位大写字母数字的那一段就是 Team ID。
    /// 例如侧载后的 `com.god.fitstate.97792VH57A` → `97792VH57A`。
    static var teamIdentifier: String? {
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        for part in bundleId.split(separator: ".") {
            if part.count == 10, part.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) {
                return String(part)
            }
        }
        return nil
    }

    /// 按优先级排列的候选 App Group ID。
    static var candidateIdentifiers: [String] {
        let suffix = configuredIdentifier.hasPrefix("group.")
            ? String(configuredIdentifier.dropFirst("group.".count))
            : configuredIdentifier

        var list: [String] = []
        if let team = teamIdentifier {
            // 门户里按「前缀 group.<TeamID> + 后缀」建出来的标准形式
            list.append("group.\(team).\(suffix)")
            // 少数情况下签名工具把整串当后缀再补一次前缀
            list.append("group.\(team).group.\(suffix)")
        }
        list.append(configuredIdentifier)
        if configuredIdentifier != fallbackIdentifier {
            list.append(fallbackIdentifier)
        }

        var seen = Set<String>()
        return list.filter { seen.insert($0).inserted }
    }

    /// 实际生效的 App Group ID；探测不到时退回构建期配置值。
    static var identifier: String {
        resolvedIdentifier ?? configuredIdentifier
    }

    /// 能真正打开容器的那个 App Group ID。
    static var resolvedIdentifier: String? {
        for id in candidateIdentifiers {
            if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil {
                return id
            }
        }
        return nil
    }

    static var containerURL: URL? {
        for id in candidateIdentifiers {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
                return url
            }
        }
        return nil
    }

    static var isAvailable: Bool { containerURL != nil }
}
