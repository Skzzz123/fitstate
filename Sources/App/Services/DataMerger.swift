import Foundation

/// 多个数据源合并成同一天。
///
/// 为什么不能「按天整条去重」
/// ------------------------
/// 早先的合并规则是「同一天谁优先级高就整条用谁的」：
/// HealthKit > 快捷指令 > CSV。
///
/// 问题在于**同一天里，不同来源覆盖的指标并不一样**：
/// 快捷指令那次跑，HRV 和静息心率通了，但睡眠那条通道只拿到分期名、没有时长，
/// 于是快捷指令写下来的这一天是「有 HRV、有心率、但睡眠 = 0」。
///
/// 如果按整天取一条，CSV 里那天的睡眠（时长、深睡、REM 全都有）
/// 就会被整条丢掉 —— 结果是**今天明明有睡眠数据，App 却显示睡眠 0 分钟**，
/// 睡眠这一维（35% 权重）直接从评分里消失。
///
/// 规则
/// ----
/// - **逐字段**取：优先级高的来源有值就用它的，没有才用低优先级的；
/// - **睡眠四项整组处理**（总时长 / 深睡 / REM / 在床），绝不拆开混搭 ——
///   拿 A 来源的时长配 B 来源的深睡，算出来的「修复性睡眠比例」是假的。
enum DataMerger {

    /// 把同一天的 `preferred`（优先级高）和 `fallback`（优先级低）合成一条。
    ///
    /// - Parameters:
    ///   - preferred: 优先级高的那一条。
    ///   - fallback: 优先级低的那一条，用来补 `preferred` 缺的部分。
    static func merge(preferred: DailyMetrics, fallback: DailyMetrics) -> DailyMetrics {
        var out = preferred

        // —— 数值指标：谁有值用谁的值
        if out.hrvMS == nil { out.hrvMS = fallback.hrvMS }
        if out.restingHR == nil { out.restingHR = fallback.restingHR }

        // —— 睡眠：整组换，不混搭
        // 优先级的来源只要有睡眠，就整组用它（含 0 时长的可能性由 hasSleepData 判定）；
        // 完全没有睡眠时才用低优先级来源的整组。
        if !out.hasSleepData && fallback.hasSleepData {
            out.totalSleep = fallback.totalSleep
            out.deepSleep = fallback.deepSleep
            out.remSleep = fallback.remSleep
            out.coreSleep = fallback.coreSleep
            out.unspecifiedSleep = fallback.unspecifiedSleep
            out.awakeInBed = fallback.awakeInBed
            out.inBed = fallback.inBed
        }

        // —— 训练记录：优先级的没有就用低优先级的
        if out.workouts.isEmpty { out.workouts = fallback.workouts }

        return out
    }

    /// 把多个来源合成一份按天去重的数据。
    ///
    /// - Parameter sources: 按优先级从高到低排列（如 [HealthKit, 快捷指令, CSV]）。
    static func merge(sources: [[DailyMetrics]]) -> [DailyMetrics] {
        var byDay: [String: DailyMetrics] = [:]
        for source in sources {
            for day in source {
                if let existing = byDay[day.dayKey] {
                    byDay[day.dayKey] = merge(preferred: existing, fallback: day)
                } else {
                    byDay[day.dayKey] = day
                }
            }
        }
        return byDay.values.sorted { $0.dayKey < $1.dayKey }
    }
}
