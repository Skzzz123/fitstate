import Foundation

/// 用户可调项。刻意保持极少：只有目标睡眠时长和基线窗口。
/// 评分权重与曲线陡峭程度是固定的，避免「调参调到不看分数」。
struct AppSettings: Codable, Equatable {
    /// 目标睡眠时长（分钟）
    var sleepGoalMinutes: Int = 450
    /// 基线窗口天数
    var baselineWindowDays: Int = 30

    static let baselineWindows = [14, 30, 60]

    static let `default` = AppSettings()

    private static let storageKey = "fitstate.settings.v1"

    var sleepGoalSeconds: TimeInterval {
        TimeInterval(sleepGoalMinutes) * 60
    }

    func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: AppSettings.storageKey),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: AppSettings.storageKey)
    }
}
