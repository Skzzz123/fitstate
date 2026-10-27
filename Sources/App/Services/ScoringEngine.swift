import Foundation

/// 评分引擎。
///
/// 核心原则：HRV / 静息心率这类指标必须跟「自己的过去」比才有意义，
/// 所以每一项先转成相对基线的偏离，再换算成 0–100 分，最后加权。
enum ScoringEngine {

    // MARK: - 入口

    static func evaluate(today: DailyMetrics, baseline: Baseline, settings: AppSettings) -> ScoreBreakdown {
        let raw = [
            rawDimension(.hrv, today: today, baseline: baseline),
            rawDimension(.sleep, today: today, baseline: baseline, settings: settings),
            rawDimension(.restingHR, today: today, baseline: baseline)
        ]

        let present = raw.filter { $0.score != nil }
        let missing = raw.filter { $0.score == nil }.map { $0.key }
        let totalWeight = present.reduce(0.0) { $0 + $1.key.defaultWeight }

        let dimensions: [DimensionScore] = present.map { item in
            let normalized = totalWeight > 0 ? item.key.defaultWeight / totalWeight : 0
            let value = item.score ?? 0
            return DimensionScore(
                key: item.key,
                label: item.key.label,
                score: value,
                weight: normalized,
                contribution: normalized * (value - 50),
                todayText: item.todayText,
                baselineText: item.baselineText,
                deltaText: item.deltaText,
                isDrag: value < 50
            )
        }

        guard !dimensions.isEmpty else {
            return ScoreBreakdown(
                generatedAt: Date(),
                dayKey: today.dayKey,
                score: nil,
                tier: nil,
                headline: "数据不足，还算不出今天的分数",
                advice: "确认昨晚戴了表，并已授予健康数据读取权限。",
                dimensions: [],
                missing: missing,
                baselineNote: baseline.progressText
            )
        }

        let score = dimensions.reduce(0.0) { $0 + $1.weight * $1.score }
        let tier = ReadinessTier.from(score: score)

        let baselineNote: String
        if baseline.isReady {
            baselineNote = baseline.progressText
        } else {
            baselineNote = "\(baseline.progressText) · 参考度较低"
        }

        return ScoreBreakdown(
            generatedAt: Date(),
            dayKey: today.dayKey,
            score: score,
            tier: tier,
            headline: headline(today: today, baseline: baseline, dimensions: dimensions, tier: tier),
            advice: advice(tier: tier, dimensions: dimensions),
            dimensions: dimensions,
            missing: missing,
            baselineNote: baselineNote
        )
    }

    // MARK: - 各维度算法

    /// HRV：对数化 z 分。HRV 呈右偏分布，取对数后「高于/低于基线」才对称。
    /// ±15% 记为 1 个标准差。
    private static func hrvScore(today: DailyMetrics, baseline: Baseline) -> Double? {
        guard let value = today.hrvMS, value > 0,
              let base = baseline.hrvMedian, base > 0 else { return nil }
        let z = log(value / base) / log(1.15)
        return clamp(50 + 22 * z)
    }

    /// 睡眠：时长 45% + 效率 25% + 分期 30%
    private static func sleepScore(today: DailyMetrics, baseline: Baseline, settings: AppSettings) -> Double? {
        guard today.hasSleepData else { return nil }

        let goal = max(settings.sleepGoalSeconds, 1)
        let ratio = min(1.0, today.totalSleep / goal)
        let durationPart = clamp(100 * pow(ratio, 1.6))

        let efficiencyPart = today.sleepEfficiency.map { clamp($0 * 100) } ?? 70.0

        let stagePart: Double
        if let ratio = today.restorativeRatio {
            let baseRatio: Double
            if let sleepMedian = baseline.sleepMedian, sleepMedian > 0,
               let deep = baseline.deepMedian, let rem = baseline.remMedian {
                baseRatio = min(1.0, (deep + rem) / sleepMedian)
            } else {
                baseRatio = 0.38   // 缺少个人基线时用通用参考：深睡 ~16% + REM ~22%
            }
            let z = (ratio - baseRatio) / 0.06
            stagePart = clamp(50 + 25 * z)
        } else {
            stagePart = 50
        }

        return 0.45 * durationPart + 0.25 * efficiencyPart + 0.30 * stagePart
    }

    /// 静息心率：低于基线是好事。±3% 记为 1 个标准差。
    private static func restingHRScore(today: DailyMetrics, baseline: Baseline) -> Double? {
        guard let value = today.restingHR, value > 0,
              let base = baseline.rhrMedian, base > 0 else { return nil }
        let z = (base - value) / (0.03 * base)
        return clamp(50 + 18 * z)
    }

    // MARK: - 文本生成

    private static func headline(today: DailyMetrics, baseline: Baseline, dimensions: [DimensionScore], tier: ReadinessTier) -> String {
        guard let drag = dimensions.filter({ $0.isDrag }).min(by: { $0.score < $1.score }) else {
            // 没有拖累项：挑最强的那个说
            if let best = dimensions.max(by: { $0.score < $1.score }) {
                switch best.key {
                case .hrv: return "HRV 高于基线，恢复状态不错"
                case .sleep: return "睡得好，修复跑够了"
                case .restingHR: return "静息心率低于基线，身体在恢复中"
                }
            }
            return "今天状态平稳"
        }

        switch drag.key {
        case .hrv:
            let drop = dropRatio(today.hrvMS, baseline.hrvMedian)
            if drop > 0.12 { return "HRV 比基线低 \(Fmt.percent(drop))，身体明显透支了" }
            return "HRV 比基线低 \(Fmt.percent(drop))，自主神经恢复还没跟上"
        case .sleep:
            let sleepMinutes = Int((today.totalSleep / 60).rounded())
            if today.deepSleep > 0, today.deepSleep < (baseline.deepMedian ?? 0) * 0.7 {
                return "昨晚只睡了 \(sleepMinutes) 分钟，深睡仅 \(Fmt.duration(today.deepSleep))"
            }
            return "昨晚只睡了 \(sleepMinutes) 分钟，睡眠债还没还上"
        case .restingHR:
            if let value = today.restingHR, let base = baseline.rhrMedian {
                return "静息心率比基线高 \(Int((value - base).rounded()))，身体还在疲劳里"
            }
            return "静息心率高于基线，身体还在疲劳里"
        }
    }

    private static func advice(tier: ReadinessTier, dimensions: [DimensionScore]) -> String {
        let base: String
        switch tier {
        case .excellent: base = "今天可以上强度，安排大重量或高强度间歇。"
        case .good: base = "正常训练，按原计划来。"
        case .average: base = "把强度降一档，容量减两成，别冲重量。"
        case .poor: base = "只做轻量活动：拉伸、快走、瑜伽就够了。"
        case .rest: base = "今天休息。散步和拉伸就够了。"
        }

        guard let drag = dimensions.filter({ $0.isDrag }).min(by: { $0.score < $1.score }) else { return base }

        let hint: String
        switch drag.key {
        case .hrv: hint = "HRV 是今天的短板"
        case .sleep: hint = "睡眠是今天的短板"
        case .restingHR: hint = "静息心率是今天的短板"
        }
        return "\(base)（\(hint)）"
    }

    // MARK: - 辅助

    private struct RawDimension {
        let key: DimensionKey
        let score: Double?
        let todayText: String
        let baselineText: String
        let deltaText: String
    }

    private static func rawDimension(
        _ key: DimensionKey,
        today: DailyMetrics,
        baseline: Baseline,
        settings: AppSettings = .default
    ) -> RawDimension {
        switch key {
        case .hrv:
            let score = hrvScore(today: today, baseline: baseline)
            let delta = ratio(today.hrvMS, baseline.hrvMedian)
            let deltaText: String
            if let delta {
                deltaText = delta >= 0 ? "高于基线 \(Fmt.percent(delta))" : "低于基线 \(Fmt.percent(-delta))"
            } else {
                deltaText = "无基线对比"
            }
            return RawDimension(
                key: key,
                score: score,
                todayText: Fmt.ms(today.hrvMS),
                baselineText: Fmt.ms(baseline.hrvMedian),
                deltaText: deltaText
            )

        case .sleep:
            let score = sleepScore(today: today, baseline: baseline, settings: settings)
            var todayText = Fmt.duration(today.totalSleep)
            if today.deepSleep > 0 { todayText += " · 深睡 \(Fmt.duration(today.deepSleep))" }
            var baselineText = Fmt.duration(baseline.sleepMedian ?? 0)
            if let deep = baseline.deepMedian, deep > 0 { baselineText += " · 深睡 \(Fmt.duration(deep))" }
            let deltaText: String
            if let value = baseline.sleepMedian, baseline.sleepMedian > 0 {
                let diff = today.totalSleep - baseline.sleepMedian
                deltaText = diff >= 0 ? "高于基线 \(Fmt.duration(diff))" : "低于基线 \(Fmt.duration(-diff))"
            } else {
                deltaText = "无基线对比"
            }
            return RawDimension(
                key: key,
                score: score,
                todayText: todayText,
                baselineText: baselineText,
                deltaText: deltaText
            )

        case .restingHR:
            let score = restingHRScore(today: today, baseline: baseline)
            let delta = ratio(today.restingHR, baseline.rhrMedian)
            let deltaText: String
            if let delta {
                // 静息心率是「越低越好」，所以文案反过来写
                deltaText = delta <= 0 ? "优于基线 \(Fmt.percent(-delta))" : "高于基线 \(Fmt.percent(delta))"
            } else {
                deltaText = "无基线对比"
            }
            return RawDimension(
                key: key,
                score: score,
                todayText: Fmt.bpm(today.restingHR),
                baselineText: Fmt.bpm(baseline.rhrMedian),
                deltaText: deltaText
            )
        }
    }

    private static func ratio(_ value: Double?, _ base: Double?) -> Double? {
        guard let value, let base, base > 0 else { return nil }
        return value / base - 1.0
    }

    private static func dropRatio(_ value: Double?, _ base: Double?) -> Double {
        guard let value, let base, base > 0 else { return 0 }
        return max(0, 1 - value / base)
    }

    static func clamp(_ value: Double, lower: Double = 0, upper: Double = 100) -> Double {
        min(upper, max(lower, value))
    }
}
