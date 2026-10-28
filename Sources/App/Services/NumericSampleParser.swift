import Foundation

/// 从「快捷指令」输出的文本里抽取数值，并做中位数 / 平均。
///
/// 背景：「查找健康记录」一次会返回**一整天几十条样本**，
/// 而 App Intent 的参数是单个数字，硬塞只会取到列表里的某一条（基本等于随机）。
/// 所以让快捷指令把整个输出塞进来，这里统一抽数值再聚合——
/// HRV 取**中位数**（抗离群值），静息心率取**平均**，跟 HealthKit 直读口径一致。
enum NumericSampleParser {

    /// 独立数值 token。
    ///
    /// 刻意排除两类：
    ///   - 日期：2026-10-28 里的 2026 / 10 / 28（都紧挨着「-」）
    ///   - 时间：23:12:00 里的 23 / 12 / 00（都紧挨着「:」）
    private static let valueRegex: NSRegularExpression? = {
        let pattern = #"(?<![\d:.\-])\d+(?:\.\d+)?(?![\d:.\-])"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    /// 文本里所有独立数值的字符串形式
    static func rawValues(in text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let regex = valueRegex else { return [] }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        var result: [String] = []
        for match in regex.matches(in: trimmed, range: range) {
            guard let swiftRange = Range(match.range, in: trimmed) else { continue }
            result.append(String(trimmed[swiftRange]))
        }
        return result
    }

    /// 文本里所有独立数值（转成 Double，剔掉非法的）
    static func values(in text: String) -> [Double] {
        rawValues(in: text).compactMap { Double($0) }
    }

    /// 中位数：HRV 用它，抗离群值。
    static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter { $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return nil }
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }

    /// 平均值：静息心率用它。
    static func average(_ values: [Double]) -> Double? {
        let valid = values.filter { $0 > 0 }
        guard !valid.isEmpty else { return nil }
        return valid.reduce(0, +) / Double(valid.count)
    }

    /// 文本里有没有提到某个单位（用来判断这批样本属于 HRV 还是静息心率）。
    static func mentions(_ text: String, _ needles: [String]) -> Bool {
        let lower = text.lowercased()
        return needles.contains { lower.contains($0) }
    }
}
