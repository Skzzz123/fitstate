import Foundation

/// 把「本该是数字」的快捷指令参数（现在是文本框）安全地变成数值。
///
/// 背景：这是一个真实踩过的坑
/// ----------------------------
/// 原来 6 个参数是 `Double`。用户把「查找健康记录」的输出接上去时，
/// 快捷指令会在**调用 Intent 之前**就抛「无法将文本转换为数字」而中止 ——
/// Intent 根本没被调起来，App 里一条数据都没有，回执也看不到。
///
/// 所以参数全改成文本框：接什么都不报错。
/// 但「接什么都能用」≠「接什么都往里写」：
/// 这里只接受**明显合理**的值，其余一律忽略，并在回执里说明原因，
/// 绝不让脏数据污染 30 天基线。
///
/// 判断「合理」的三个依据
/// ----------------------
///   1. 形态对：单值参数必须是「一个数字」，不能是时间、不能是带分期名的段落；
///   2. 通道对：文本里出现睡眠分期名 → 说明接错通道了，直接拒绝；
///   3. 量级对：HRV / 静息心率必须落在可信区间里。
enum IntentValueParser {

    /// HRV 的可信区间（毫秒）。
    static let hrvRange: ClosedRange<Double> = 5...500
    /// 静息心率的可信区间（次/分）。
    static let rhrRange: ClosedRange<Double> = 25...220

    // MARK: - 单值参数（分钟）

    /// 睡眠时长 / 深睡 / REM / 在床：只接受「一个数字」（可以带「分钟 / min」）。
    ///
    /// 「22:30」「深睡 1 小时」这种一律拒绝 ——
    /// 前者是把**时间**当成了分钟，后者是接错了通道。
    static func minutes(from text: String) -> Double? {
        let normalized = normalizeDigits(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normalized.isEmpty else { return nil }

        var body = normalized
        let lower = body.lowercased()
        for unit in ["分钟", "min", "mins", "m"] where lower.hasSuffix(unit) {
            body = String(body.dropLast(unit.count)).trimmingCharacters(in: .whitespaces)
            break
        }

        guard isPureNumber(body), let value = Double(body), value >= 0, value <= 24 * 60 else {
            return nil
        }
        return value
    }

    // MARK: - 指标参数（HRV / 静息心率）

    /// HRV / 静息心率参数。
    ///
    /// 接受两种形态：
    ///   1. 一个数字：「48」
    ///   2. 一批样本：「48 毫秒, 52 毫秒」→ HRV 取中位数、静息心率取平均
    ///
    /// 带睡眠分期名的文本一律拒绝（那说明接错通道了，
    /// 比如把睡眠那段合并文本接到了 HRV 上）。
    static func metric(from text: String, kind: HealthTextParser.SampleKind) -> Double? {
        let normalized = normalizeDigits(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normalized.isEmpty else { return nil }

        // 接错通道的信号：文本里有睡眠分期名
        if SleepStage.detect(normalized) != nil { return nil }

        let lower = normalized.lowercased()
        let hasHRVUnit = normalized.contains("毫秒") || lower.contains("ms") || lower.contains("millisecond")
        let hasRHRUnit = normalized.contains("次/分") || normalized.contains("次／分") || normalized.contains("次每分")
            || normalized.contains("拍/分") || lower.contains("bpm") || lower.contains("count/min")

        // 单位指向别的指标 → 接错通道了，拒绝
        switch kind {
        case .hrv: if hasRHRUnit { return nil }
        case .rhr: if hasHRVUnit { return nil }
        default: return nil
        }

        let parsed = HealthTextParser.parse(normalized, hint: kind)
        var values: [Double]
        switch kind {
        case .hrv: values = parsed.hrvValues.filter { hrvRange.contains($0) }
        case .rhr: values = parsed.rhrValues.filter { rhrRange.contains($0) }
        default: values = []
        }
        guard !values.isEmpty else { return nil }

        // 没有单位、又不是单个数字 → 分不清是哪个指标，一概拒绝
        // （宁可回落到原始文本通道，那边知道自己是哪个指标）
        if !hasHRVUnit && !hasRHRUnit && values.count > 1 { return nil }

        switch kind {
        case .hrv: return NumericSampleParser.median(values)
        case .rhr: return NumericSampleParser.average(values)
        default: return nil
        }
    }

    // MARK: - 杂项

    /// 空白判定（快捷指令里「没接」的参数是空字符串）。
    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 全角数字转半角（中文界面偶尔会出现）。
    private static func normalizeDigits(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            if scalar.value >= 0xFF10 && scalar.value <= 0xFF19 {
                result.append(Character(UnicodeScalar(scalar.value - 0xFEE0)!))
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// 是不是「纯数字」（允许一个小数点）。
    private static func isPureNumber(_ text: String) -> Bool {
        var hasDigit = false
        var hasDot = false
        for ch in text {
            if ch.isASCII && ch.isNumber {
                hasDigit = true
                continue
            }
            if ch == "." {
                if hasDot { return false }
                hasDot = true
                continue
            }
            return false
        }
        return hasDigit
    }
}
