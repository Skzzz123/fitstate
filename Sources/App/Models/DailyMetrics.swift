import Foundation

/// 单日的健康数据汇总。所有时长单位为秒。
struct DailyMetrics: Codable, Identifiable, Equatable {
    var id: String { dayKey }

    /// 形如 "2026-10-27"
    let dayKey: String
    let date: Date

    var totalSleep: TimeInterval = 0
    var deepSleep: TimeInterval = 0
    var remSleep: TimeInterval = 0
    var coreSleep: TimeInterval = 0
    var unspecifiedSleep: TimeInterval = 0
    var awakeInBed: TimeInterval = 0
    var inBed: TimeInterval = 0

    /// 夜间 HRV（SDNN，单位 ms）
    var hrvMS: Double? = nil
    /// 当日静息心率（bpm）
    var restingHR: Double? = nil

    var workouts: [WorkoutSummary] = []

    var hasSleepData: Bool { totalSleep > 0 }
    var deepPlusREM: TimeInterval { deepSleep + remSleep }

    /// 睡眠效率 = 实际睡着 / 在床时长
    var sleepEfficiency: Double? {
        guard totalSleep > 0 else { return nil }
        let denominator = inBed > 0 ? inBed : (totalSleep + awakeInBed)
        guard denominator > 0 else { return nil }
        return min(1.0, max(0.0, totalSleep / denominator))
    }

    /// 深睡 + REM 占总睡眠的比例
    var restorativeRatio: Double? {
        guard totalSleep > 0 else { return nil }
        return min(1.0, deepPlusREM / totalSleep)
    }
}

/// 训练记录（只读，不写回「健康」）
struct WorkoutSummary: Codable, Identifiable, Equatable {
    var id: String { "\(start.timeIntervalSince1970)-\(activity)" }

    let activity: String
    let start: Date
    let duration: TimeInterval
    let energyKcal: Double?

    var displayName: String {
        WorkoutSummary.displayNames[activity] ?? activity
    }

    static let displayNames: [String: String] = [
        "traditionalStrengthTraining": "力量训练",
        "functionalStrengthTraining": "功能力量",
        "highIntensityIntervalTraining": "高强度间歇",
        "coreTraining": "核心训练",
        "running": "跑步",
        "walking": "步行",
        "cycling": "骑行",
        "swimming": "游泳",
        "rowing": "划船",
        "elliptical": "椭圆机",
        "stairClimbing": "爬楼",
        "yoga": "瑜伽",
        "pilates": "普拉提",
        "flexibility": "柔韧训练",
        "mindAndBody": "身心训练",
        "mixedCardio": "混合有氧",
        "cardio": "有氧",
        "jumpRope": "跳绳",
        "basketball": "篮球",
        "badminton": "羽毛球",
        "tableTennis": "乒乓球",
        "tennis": "网球",
        "boxing": "拳击",
        "martialArts": "武术",
        "climbing": "攀岩",
        "skatingSports": "滑冰",
        "snowSports": "雪上运动",
        "hiking": "徒步",
        "cooldown": "整理放松",
        "preparationAndRecovery": "热身与恢复"
    ]
}
