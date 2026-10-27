import Foundation

/// 主 App 写入、Widget 读取的共享快照。
/// 保持 Codable 且字段尽量少，Widget 不依赖任何 HealthKit 调用。
struct FitStateSnapshot: Codable, Equatable {
    var generatedAt: Date
    var dayKey: String
    var score: Double?
    var tier: String?
    var headline: String?
    var advice: String?
    var metrics: [SnapshotMetric]
    var baselineNote: String?

    static var empty: FitStateSnapshot {
        FitStateSnapshot(
            generatedAt: Date(),
            dayKey: "",
            score: nil,
            tier: nil,
            headline: nil,
            advice: nil,
            metrics: [],
            baselineNote: nil
        )
    }

    /// 小组件在画廊里展示的占位数据
    static var preview: FitStateSnapshot {
        FitStateSnapshot(
            generatedAt: Date(),
            dayKey: "2026-01-01",
            score: 61,
            tier: "一般",
            headline: "HRV 比基线低 8.7%，自主神经恢复还没跟上",
            advice: "把强度降一档，容量减两成，别冲重量。",
            metrics: [
                SnapshotMetric(key: "sleep", label: "睡眠", score: 89, valueText: "7h52m · 深睡 1h06m", baselineText: "7h30m", deltaText: "高于基线 22m", isDrag: false),
                SnapshotMetric(key: "hrv", label: "HRV", score: 36, valueText: "42ms", baselineText: "46ms", deltaText: "低于基线 8.7%", isDrag: true),
                SnapshotMetric(key: "restingHR", label: "心率", score: 60, valueText: "57 bpm", baselineText: "58 bpm", deltaText: "优于基线 1.7%", isDrag: false)
            ],
            baselineNote: "基线 30 天"
        )
    }
}

struct SnapshotMetric: Codable, Equatable, Identifiable {
    var id: String { key }
    var key: String
    var label: String
    var score: Double?
    var valueText: String
    var baselineText: String
    var deltaText: String
    var isDrag: Bool
}
