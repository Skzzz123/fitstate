import Foundation

/// 个人基线：所有比较都以「你自己的过去」为参照。
struct Baseline: Equatable {
    var hrvMedian: Double?
    var hrvP25: Double?
    var hrvP75: Double?

    var rhrMedian: Double?
    var rhrP25: Double?
    var rhrP75: Double?

    var sleepMedian: TimeInterval?
    var sleepP25: TimeInterval?
    var sleepP75: TimeInterval?

    var deepMedian: TimeInterval?
    var remMedian: TimeInterval?
    var efficiencyMedian: Double?

    /// 参与基线计算的有效天数
    var sampleCount: Int = 0

    /// 至少需要 7 天才敢给出结论
    static let minimumSamples = 7

    var isReady: Bool { sampleCount >= Baseline.minimumSamples }

    var progressText: String {
        isReady ? "基线 \(sampleCount) 天" : "基线建立中 \(sampleCount)/\(Baseline.minimumSamples)"
    }
}

/// 基线计算引擎：滚动窗口 + 中位数 + 分位带。
enum BaselineEngine {
    /// 计算基线时排除当天，避免今天的数值反向污染自己的参照系。
    static func build(from metrics: [DailyMetrics], windowDays: Int, excluding dayKey: String?) -> Baseline {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let candidates = metrics
            .filter { $0.dayKey != dayKey }
            .filter { $0.date <= today }
            .sorted { $0.date < $1.date }
            .suffix(windowDays)

        var baseline = Baseline()

        let hrvValues = candidates.compactMap { $0.hrvMS }
        let rhrValues = candidates.compactMap { $0.restingHR }
        let sleepValues = candidates.filter { $0.hasSleepData }.map { $0.totalSleep }
        let deepValues = candidates.filter { $0.deepSleep > 0 }.map { $0.deepSleep }
        let remValues = candidates.filter { $0.remSleep > 0 }.map { $0.remSleep }
        let efficiencyValues = candidates.compactMap { $0.sleepEfficiency }

        baseline.hrvMedian = Stats.median(hrvValues)
        baseline.hrvP25 = Stats.percentile(hrvValues, 0.25)
        baseline.hrvP75 = Stats.percentile(hrvValues, 0.75)

        baseline.rhrMedian = Stats.median(rhrValues)
        baseline.rhrP25 = Stats.percentile(rhrValues, 0.25)
        baseline.rhrP75 = Stats.percentile(rhrValues, 0.75)

        baseline.sleepMedian = Stats.median(sleepValues)
        baseline.sleepP25 = Stats.percentile(sleepValues, 0.25)
        baseline.sleepP75 = Stats.percentile(sleepValues, 0.75)

        baseline.deepMedian = Stats.median(deepValues)
        baseline.remMedian = Stats.median(remValues)
        baseline.efficiencyMedian = Stats.median(efficiencyValues)

        // 有效样本数：至少有睡眠或 HRV 之一
        baseline.sampleCount = candidates.filter { $0.hasSleepData || $0.hrvMS != nil }.count

        return baseline
    }
}

/// 基础统计工具。中位数抗离群值，是个人基线的首选。
enum Stats {
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }

    // 注意：TimeInterval 就是 Double，这里只能有一个 median 重载，
    // 否则 Swift 会报 invalid redeclaration。
    static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        if sorted.count == 1 { return sorted[0] }
        let rank = max(0, min(1, p)) * Double(sorted.count - 1)
        let lower = Int(floor(rank))
        let upper = Int(ceil(rank))
        if lower == upper { return sorted[lower] }
        let weight = rank - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
