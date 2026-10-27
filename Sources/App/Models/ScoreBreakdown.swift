import Foundation

/// 分档
enum ReadinessTier: String, Codable, CaseIterable {
    case excellent
    case good
    case average
    case poor
    case rest

    var label: String {
        switch self {
        case .excellent: return "极佳"
        case .good: return "良好"
        case .average: return "一般"
        case .poor: return "欠佳"
        case .rest: return "建议休息"
        }
    }

    /// 训练建议
    var advice: String {
        switch self {
        case .excellent: return "可以上强度"
        case .good: return "正常训练"
        case .average: return "降强度控量"
        case .poor: return "只做轻量活动"
        case .rest: return "今天休息"
        }
    }

    static func from(score: Double) -> ReadinessTier {
        switch score {
        case 85...: return .excellent
        case 70..<85: return .good
        case 55..<70: return .average
        case 40..<55: return .poor
        default: return .rest
        }
    }
}

/// 评分维度
enum DimensionKey: String, Codable, CaseIterable {
    case hrv
    case sleep
    case restingHR

    var label: String {
        switch self {
        case .hrv: return "HRV"
        case .sleep: return "睡眠"
        case .restingHR: return "静息心率"
        }
    }

    /// 默认权重：HRV 40% · 睡眠 35% · 静息心率 25%（固定，不开放调节）
    var defaultWeight: Double {
        switch self {
        case .hrv: return 0.40
        case .sleep: return 0.35
        case .restingHR: return 0.25
        }
    }
}

/// 单个维度的得分明细
struct DimensionScore: Codable, Equatable, Identifiable {
    var id: String { key.rawValue }

    let key: DimensionKey
    let label: String
    /// 0–100
    let score: Double
    /// 归一化后的实际权重（缺失项会被剔除并重新归一化）
    let weight: Double
    /// 对总分的贡献 = weight × (score − 50)
    let contribution: Double
    let todayText: String
    let baselineText: String
    let deltaText: String
    /// 是否是今天的拖累项
    let isDrag: Bool
}

/// 今日评分结果
struct ScoreBreakdown: Codable, Equatable {
    let generatedAt: Date
    let dayKey: String

    /// 0–100，nil 表示数据不足以评分
    let score: Double?
    let tier: ReadinessTier?
    let headline: String
    let advice: String
    let dimensions: [DimensionScore]
    /// 权重归一化前被剔除的维度（数据缺失）
    let missing: [DimensionKey]
    let baselineNote: String

    var hasScore: Bool { score != nil }

    /// 按分数从低到高排，最低的即为拖累项
    var sortedDimensions: [DimensionScore] {
        dimensions.sorted { $0.score < $1.score }
    }

    var topDrag: DimensionScore? {
        sortedDimensions.first(where: { $0.isDrag })
    }
}
