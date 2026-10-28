import Foundation

/// 睡眠样本的分类。
enum SleepStage {
    case deep, rem, core, unspecified, awake, inBed

    /// 从样本的 Value 文本里认出分类。
    static func detect(_ raw: String) -> SleepStage? {
        let v = raw.lowercased()
        if v.contains("asleepdeep") || v.contains("深睡") { return .deep }
        if v.contains("asleeprem") || v.contains("rem") || v.contains("快速眼动") { return .rem }
        if v.contains("asleepcore") || v.contains("核心") { return .core }
        if v.contains("asleepunspecified") || v.contains("未分期") { return .unspecified }
        if v.contains("inbed") || v.contains("在床") { return .inBed }
        if v.contains("awake") || v.contains("清醒") { return .awake }
        return nil
    }
}

/// 从「快捷指令」导出的睡眠分析原始数据里解析出各段时长。
///
/// 为什么需要它
/// ------------
/// 「查找健康记录」选「睡眠分析」返回的是**一堆样本**（深睡、REM、核心、清醒、在床…），
/// 要在快捷指令里靠「筛选 → 时长 → 求和」把每个分类加起来，要拖十来个动作，
/// 每天都做一遍不现实。
///
/// 所以这里换了个思路：让快捷指令把原始输出整包丢过来，解析在 App 内部做。
/// 解析失败也不会污染数据 —— 解析不出来就保持参数里的原值。
///
/// 能识别的形态（按顺序尝试）：
///   1. JSON 数组：`[{"Start Date":"...","End Date":"...","Value":" asleepDeep "}, …]`
///   2. JSON 对象数组（分行或连写）
///   3. 纯文本：每条记录里有两个日期 + 一个分类关键词
enum SleepSampleParser {

    struct Summary {
        var totalSleep: TimeInterval = 0
        var deepSleep: TimeInterval = 0
        var remSleep: TimeInterval = 0
        var coreSleep: TimeInterval = 0
        var unspecifiedSleep: TimeInterval = 0
        var awakeInBed: TimeInterval = 0
        var inBed: TimeInterval = 0
        var sampleCount = 0

        var isEmpty: Bool { sampleCount == 0 }

        /// 实际睡着（深睡 + REM + 核心 + 未分期）
        var asleep: TimeInterval { totalSleep }
    }

    // MARK: - 入口

    static func parse(_ text: String) -> Summary {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Summary() }

        if let fromJSON = parseJSON(trimmed), !fromJSON.isEmpty {
            return fromJSON
        }
        let fromText = parsePlainText(trimmed)
        return fromText
    }

    // MARK: - JSON 路径

    private static func parseJSON(_ text: String) -> Summary? {
        // 找出最外层的 [ … ]
        guard let first = text.firstIndex(of: "["), let last = text.lastIndex(of: "]"), first < last else {
            return nil
        }
        let slice = String(text[first...last])
        guard let data = slice.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        var items: [Any] = []
        if let array = object as? [Any] {
            items = array
        } else if let dict = object as? [String: Any] {
            items = [dict]
        }
        return summarize(items)
    }

    // MARK: - 纯文本路径

    private static func parsePlainText(_ text: String) -> Summary {
        // 按 } ] 或换行切分，每段当成一条记录
        let chunks = text
            .split(whereSeparator: { $0 == "}" || $0 == "]" || $0 == "\n" || $0 == "\r" || $0 == "," })
            .map(String.init)

        var items: [[String: Any]] = []
        for chunk in chunks {
            guard let kind = firstKind(in: chunk) else { continue }
            let dates = findDates(in: chunk)
            guard dates.count >= 2 else { continue }
            items.append([
                "kind": kind,
                "start": dates[0],
                "end": dates[1]
            ])
        }
        return summarize(items)
    }

    private static func firstKind(in text: String) -> String? {
        let lower = text.lowercased()
        for key in ["asleepdeep", "asleeprem", "asleepcore", "asleepunspecified", "inbed", "awake",
                    "深睡", "快速眼动", "核心", "未分期", "在床", "清醒"] {
            if lower.contains(key) {
                return key
            }
        }
        return nil
    }

    // MARK: - 日期提取

    private static let dateRegex: NSRegularExpression? = {
        let pattern = #"\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:\s*(?:Z|[+-]\d{2}:?\d{2}))?"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    private static let formatters: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd HH:mm:ss ZZZZZ",
            "yyyy-MM-dd HH:mm:ss Z",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss.SSSSSS ZZZZZ"
        ]
        return formats.map { fmt in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = fmt
            return f
        }
    }()

    private static func parseDate(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        for formatter in formatters {
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static func findDates(in text: String) -> [Date] {
        guard let regex = dateRegex else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var result: [Date] = []
        for match in regex.matches(in: text, range: range) {
            guard let swiftRange = Range(match.range, in: text) else { continue }
            let token = String(text[swiftRange])
            if let date = parseDate(token) { result.append(date) }
        }
        return result
    }

    // MARK: - 汇总

    private static func summarize(_ items: [Any]) -> Summary {
        var summary = Summary()
        for item in items {
            guard let dict = item as? [String: Any] else { continue }
            guard let kindRaw = dict["kind"] as? String ?? valueString(in: dict),
                  let kind = SleepStage.detect(kindRaw),
                  let start = dateValue(in: dict, keys: ["start", "Start Date", "startDate", "StartDate"]),
                  let end = dateValue(in: dict, keys: ["end", "End Date", "endDate", "EndDate"]) else {
                continue
            }
            let duration = end.timeIntervalSince(start)
            guard duration > 0 else { continue }

            summary.sampleCount += 1
            switch kind {
            case .deep:
                summary.deepSleep += duration
                summary.totalSleep += duration
            case .rem:
                summary.remSleep += duration
                summary.totalSleep += duration
            case .core:
                summary.coreSleep += duration
                summary.totalSleep += duration
            case .unspecified:
                summary.unspecifiedSleep += duration
                summary.totalSleep += duration
            case .awake:
                summary.awakeInBed += duration
            case .inBed:
                summary.inBed += duration
            }
        }

        // 「在床」有时只给一个总时长，有时给的是分段。两种都兜住。
        if summary.inBed > 0 && summary.awakeInBed > 0 && summary.inBed < summary.totalSleep {
            summary.inBed = summary.totalSleep + summary.awakeInBed
        }
        return summary
    }

    /// 从字典里取 Value 字段（大小写、下划线、空格都兼容）
    private static func valueString(in dict: [String: Any]) -> String? {
        for (key, value) in dict {
            let lower = key.lowercased().replacingOccurrences(of: "_", with: "")
            if lower == "value" || lower.contains("sleepanalysis") {
                if let s = value as? String { return s }
                if let n = value as? NSNumber { return n.stringValue }
            }
        }
        return nil
    }

    private static func dateValue(in dict: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let value = dict[key] {
                if let date = value as? Date { return date }
                if let number = value as? NSNumber { return Date(timeIntervalSince1970: number.doubleValue) }
                if let text = value as? String {
                    if let date = parseDate(text) { return date }
                    if let seconds = Double(text) { return Date(timeIntervalSince1970: seconds) }
                }
            }
        }
        // 退而求其次：任何看起来像日期的字段
        for (_, value) in dict {
            if let date = value as? Date { return date }
            if let text = value as? String, let date = parseDate(text) { return date }
        }
        return nil
    }
}
