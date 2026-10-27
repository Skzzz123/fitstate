import Foundation

/// 趋势洞察：把历史数据变成「对你有用」的结论。
struct Insight: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let kind: Kind

    enum Kind: String {
        case finding
        case warning
        case neutral
    }
}

/// 每天的状态分 + 关联的训练情况，用于趋势页。
struct TrendPoint: Identifiable, Equatable {
    let id: String
    let dayKey: String
    let date: Date
    let score: Double?
    let hrvMS: Double?
    let restingHR: Double?
    let sleepSeconds: TimeInterval?
    let deepSeconds: TimeInterval?
    let hasWorkout: Bool
    let workoutNames: [String]
}

enum InsightEngine {

    /// 生成最近窗口的洞察
    static func insights(
        points: [TrendPoint],
        baseline: Baseline,
        windowDays: Int
    ) -> [Insight] {
        var results: [Insight] = []

        // ① 睡不满 vs 睡够 —— 第二天状态分的差别
        if let shortSleep = points.filter({ ($0.sleepSeconds ?? 0) < 6 * 3600 && $0.score != nil }),
           let enoughSleep = points.filter({ ($0.sleepSeconds ?? 0) >= 7.5 * 3600 && $0.score != nil }),
           shortSleep.count >= 2, enoughSleep.count >= 2 {
            let shortAvg = shortSleep.compactMap(\.score).reduce(0, +) / Double(shortSleep.count)
            let longAvg = enoughSleep.compactMap(\.score).reduce(0, +) / Double(enoughSleep.count)
            let gap = longAvg - shortAvg
            if abs(gap) >= 3 {
                let sign = gap > 0 ? "高" : "低"
                results.append(Insight(
                    id: "sleep-gap",
                    title: "睡眠时长和状态分的关系",
                    detail: "过去 \(windowDays) 天里，睡满 7.5 小时的 \(enoughSleep.count) 个夜晚，次日状态分平均比睡不满 6 小时的 \(shortSleep.count) 个夜晚\(sign) \(String(format: "%.0f", abs(gap))) 分。",
                    kind: gap > 0 ? .finding : .warning
                ))
            }
        }

        // ② 睡眠时长 vs 次日 HRV 的线性关系
        if let correlation = correlation(points: points) {
            let strength: String
            let direction: String
            if correlation > 0.3 {
                strength = "明显正相关"
                direction = "睡得越久，第二天的 HRV 越高"
            } else if correlation > 0.1 {
                strength = "弱正相关"
                direction = "睡得稍久一点，第二天的 HRV 会略高"
            } else if correlation < -0.3 {
                strength = "明显负相关"
                direction = "睡得越久，第二天的 HRV 反而越低"
            } else {
                strength = "几乎没有线性关系"
                direction = "单看睡眠时长预测不了第二天的 HRV"
            }
            if abs(correlation) >= 0.1 {
                results.append(Insight(
                    id: "sleep-hrv",
                    title: "睡眠与次日 HRV",
                    detail: "你的睡眠时长和第二天 HRV 呈\(strength)（r = \(String(format: "%.2f", correlation))）：\(direction)。",
                    kind: .neutral
                ))
            }
        }

        // ③ 低分日是否还在硬练
        let trained = points.filter { $0.hasWorkout && $0.score != nil }
        if trained.count >= 3 {
            let lowDays = trained.filter { ($0.score ?? 100) < 55 }
            let ratio = Double(lowDays.count) / Double(trained.count)
            if ratio >= 0.25 {
                results.append(Insight(
                    id: "train-low",
                    title: "你在低分日训练得比较多",
                    detail: "训练日里有 \(lowDays.count)/\(trained.count) 天状态分低于 55。这些天的训练效果可能打了折扣，可以试着把重训安排在 70 分以上的日子。",
                    kind: .warning
                ))
            } else if ratio == 0 {
                results.append(Insight(
                    id: "train-low",
                    title: "训练安排得不错",
                    detail: "你的 \(trained.count) 个训练日状态分全部在 55 分以上 —— 都在身体状态好的时候练。",
                    kind: .finding
                ))
            }
        }

        // ④ HRV 的稳定性
        if baseline.isReady, let median = baseline.hrvMedian, let p25 = baseline.hrvP25, let p75 = baseline.hrvP75, median > 0 {
            let spread = (p75 - p25) / median
            let level: String
            if spread < 0.25 {
                level = "相当稳定"
            } else if spread < 0.45 {
                level = "波动适中"
            } else {
                level = "波动偏大"
            }
            results.append(Insight(
                id: "hrv-stability",
                title: "HRV 基线特征",
                detail: "你的 HRV 中位数 \(Fmt.ms(median))，中间 50% 的数据落在 \(Fmt.ms(p25)) – \(Fmt.ms(p75)) 之间，\(level)。基线越稳定，评分越可信。",
                kind: .neutral
            ))
        }

        if results.isEmpty {
            results.append(Insight(
                id: "need-more",
                title: "还需要更多数据",
                detail: "目前积累的天数还不够形成可靠的规律。连续佩戴一周以上，这里就会给出关于睡眠、HRV 和训练的个人化结论。",
                kind: .neutral
            ))
        }

        return results
    }

    /// 睡眠时长与次日 HRV 变化的关系（用于散点图）
    static func sleepVsNextDayHRV(points: [TrendPoint]) -> [(sleep: Double, delta: Double)] {
        var result: [(Double, Double)] = []
        let sorted = points.sorted { $0.date < $1.date }
        for index in 0..<(sorted.count - 1) {
            let current = sorted[index]
            let next = sorted[index + 1]
            guard let sleep = current.sleepSeconds, let nextHRV = next.hrvMS,
                  let base = current.hrvMS, base > 0 else { continue }
            let delta = nextHRV / base - 1.0
            result.append((sleep / 3600.0, delta))
        }
        return result
    }

    /// 皮尔逊相关系数
    static func correlation(points: [TrendPoint]) -> Double? {
        let pairs: [(Double, Double)] = points.compactMap { point in
            guard let sleep = point.sleepSeconds, let hrv = point.hrvMS else { return nil }
            return (sleep / 3600.0, hrv)
        }
        guard pairs.count >= 4 else { return nil }

        let n = Double(pairs.count)
        let meanX = pairs.reduce(0.0) { $0 + $1.0 } / n
        let meanY = pairs.reduce(0.0) { $0 + $1.1 } / n

        var numerator = 0.0, dx2 = 0.0, dy2 = 0.0
        for (x, y) in pairs {
            let dx = x - meanX
            let dy = y - meanY
            numerator += dx * dy
            dx2 += dx * dx
            dy2 += dy * dy
        }
        let denominator = (dx2 * dy2).squareRoot()
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }
}
