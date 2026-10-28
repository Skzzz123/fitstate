import Foundation

/// 睡眠分期的分类。
///
/// 快捷指令「查找健康记录(睡眠分析)」返回的 Value 就是这几种枚举，
/// 中文界面上显示成「深睡 / 核心 / REM / 清醒 / 在床 / 未分期」。
enum SleepStage {
    case deep
    case rem
    case core
    case unspecified
    case awake
    case inBed

    /// 从一段文本里认出分期。中英文都认。
    ///
    /// 刻意**不**认单独的「睡眠」二字——「睡眠分析」是指标名而不是分期，
    /// 认错了会把整晚都算成「未分期」。
    static func detect(_ raw: String) -> SleepStage? {
        let v = raw.lowercased()

        if v.contains("asleepdeep") || v.contains("深睡") || v.contains("深度睡眠") { return .deep }
        if v.contains("asleeprem") || v.contains("快速眼动") || v.contains("rem睡眠") { return .rem }
        if v.contains("asleepcore") || v.contains("核心睡眠") || v.contains("核心") { return .core }
        if v.contains("asleepunspecified") || v.contains("未分期") { return .unspecified }
        if v.contains("inbed") || v.contains("在床") { return .inBed }
        if v.contains("awake") || v.contains("清醒") { return .awake }

        // 独立英文单词（asleepDeep 这类连写上面已经处理过了）
        let tokens = v.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if tokens.contains("deep") { return .deep }
        if tokens.contains("rem") { return .rem }
        if tokens.contains("core") { return .core }
        if tokens.contains("awake") { return .awake }
        if tokens.contains("inbed") { return .inBed }
        if tokens.contains("unspecified") { return .unspecified }
        return nil
    }
}

/// 「查找健康记录」输出的统一解析器。
///
/// 为什么需要它
/// ------------
/// 快捷指令里「查找健康记录」的输出**没有一个稳定格式**：
///   - 「组合文本」类型选 JSON → 一段 JSON 数组
///   - 「组合文本」类型选短文本 → 一行一条的纯文本
///   - 直接接到 App Intent → 快捷指令自己转的字符串
/// 三种都可能是，中文英文也都有可能。
///
/// 所以这里不赌单一格式，而是**分通道 + 分层**地认：
///   1. 通道（hint）告诉解析器这段是 HRV / 静息心率 / 睡眠；
///   2. 睡眠通道先找分期关键词（asleepDeep、深睡…），一段算一个样本；
///      找不到关键词就退化成「按相邻时间点两两配对」；
///   3. 数值通道先找「数值+单位」（45 毫秒），每个值一个样本；
///      找不到单位就退化成「这一行剩下的所有数字」，再靠指标名或通道定归属。
///
/// 这样无论输出长什么样，都至少能落出一个可用的数，
/// 而不是解析失败就默默记成 0。
enum HealthTextParser {

    // MARK: - 结果模型

    /// 一条记录属于哪个指标。
    enum SampleKind {
        case sleep(SleepStage)
        case hrv
        case rhr
        case unknown
    }

    /// 解析出来的一条样本。
    struct ParsedSample {
        var kind: SampleKind = .unknown
        /// hrv / rhr 的数值
        var value: Double?
        var start: Date?
        var end: Date?
        /// 睡眠分段的时长（秒）
        var duration: TimeInterval?
        var raw: String = ""
    }

    /// 睡眠分期的汇总。
    struct SleepBreakdown {
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

    /// 整段文本的解析结果。
    struct ParseOutcome {
        var samples: [ParsedSample] = []
        /// 没读懂的原始片段（给用户看，告诉他哪几行没认出来）
        var unrecognized: [String] = []
        var hrvValues: [Double] = []
        var rhrValues: [Double] = []
        var sleep = SleepBreakdown()

        var isEmpty: Bool { samples.isEmpty }

        /// 收下一条样本，按类型归类。
        mutating func add(_ sample: ParsedSample) {
            switch sample.kind {
            case .hrv:
                if let value = sample.value {
                    hrvValues.append(value)
                    samples.append(sample)
                } else {
                    unrecognized.append(sample.raw)
                }
            case .rhr:
                if let value = sample.value {
                    rhrValues.append(value)
                    samples.append(sample)
                } else {
                    unrecognized.append(sample.raw)
                }
            case .sleep(let stage):
                // 时长为 0 的分段没有意义（多半是没解析出起止时间），记成「没认出来」
                let duration = sample.duration ?? 0
                guard duration > 0 else {
                    unrecognized.append(sample.raw)
                    return
                }
                sleep.sampleCount += 1
                switch stage {
                case .deep:
                    sleep.deepSleep += duration
                    sleep.totalSleep += duration
                case .rem:
                    sleep.remSleep += duration
                    sleep.totalSleep += duration
                case .core:
                    sleep.coreSleep += duration
                    sleep.totalSleep += duration
                case .unspecified:
                    sleep.unspecifiedSleep += duration
                    sleep.totalSleep += duration
                case .awake:
                    sleep.awakeInBed += duration
                case .inBed:
                    sleep.inBed += duration
                }
                samples.append(sample)
            case .unknown:
                unrecognized.append(sample.raw)
            }
        }
    }

    // MARK: - 入口

    /// 解析「查找健康记录」的输出。
    ///
    /// - Parameter hint: 调用方已经知道这段文本属于哪个指标。
    ///   `.unknown` 表示靠内容自己猜。
    static func parse(_ text: String, hint: SampleKind = .unknown) -> ParseOutcome {
        var outcome = ParseOutcome()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return outcome }

        // 1) 先试 JSON
        if let array = jsonArray(in: trimmed) {
            for item in array {
                if let dict = item as? [String: Any] {
                    outcome.add(sample(fromDictionary: dict, hint: hint))
                } else if let string = item as? String {
                    for sample in fallbackSamples(string, hint: hint) {
                        outcome.add(sample)
                    }
                }
            }
            if !outcome.samples.isEmpty { return outcome }
            outcome = ParseOutcome()
        }

        // 2) 再按纯文本处理
        for line in trimmed.components(separatedBy: .newlines) {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            for sample in parseLine(text, hint: hint) {
                outcome.add(sample)
            }
        }

        // 3) 一条记录都没切出来，但文本里确实有数字
        //    → 整段当成一条记录（通道已知，直接归类）
        if outcome.samples.isEmpty {
            let values = NumericSampleParser.values(in: trimmed)
            if values.isEmpty {
                outcome.unrecognized.append(trimmed)
            } else {
                switch hint {
                case .hrv:
                    outcome.hrvValues = values
                case .rhr:
                    outcome.rhrValues = values
                case .sleep:
                    outcome.unrecognized.append(trimmed)
                case .unknown:
                    outcome.unrecognized.append(trimmed)
                }
            }
        }

        return outcome
    }

    // MARK: - JSON

    /// 把文本里最外层的 JSON 数组挖出来。
    private static func jsonArray(in text: String) -> [Any]? {
        guard let first = text.firstIndex(of: "["), let last = text.lastIndex(of: "]"), first < last else {
            return nil
        }
        let slice = String(text[first...last])
        guard let data = slice.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        if let array = object as? [Any] { return array }
        if let dict = object as? [String: Any] { return [dict] }
        return nil
    }

    /// 从 JSON 字典里取一条样本。
    private static func sample(fromDictionary dict: [String: Any], hint: SampleKind) -> ParsedSample {
        var sample = ParsedSample()
        sample.raw = describe(dict)

        let typeText = lookupString(dict, ["type", "类型", "kind", "category", "名称", "name"]) ?? ""
        let valueText = lookupString(dict, ["value", "值", "数值", "measurement"]) ?? ""
        let unitText = lookupString(dict, ["unit", "单位"]) ?? ""

        sample.start = lookupDate(dict, ["start date", "startdate", "start", "开始日期", "起始日期"])
        sample.end = lookupDate(dict, ["end date", "enddate", "end", "结束日期", "终止日期"])

        let numericValue = lookupNumber(dict, ["value", "值", "数值", "measurement"])

        // 先定类型：字典里的类型名最权威，其次单位，最后才是通道提示
        if let stage = SleepStage.detect(typeText) {
            sample.kind = .sleep(stage)
        } else if let stage = SleepStage.detect(valueText), typeText.lowercased().contains("sleep") || typeText.contains("睡眠") {
            sample.kind = .sleep(stage)
        } else if typeText.lowercased().contains("sleep") || typeText.contains("睡眠") {
            sample.kind = .sleep(.unspecified)
        } else if isHRVUnit(unitText) {
            sample.kind = .hrv
        } else if isRHRUnit(unitText) {
            sample.kind = .rhr
        } else if isHRVName(typeText) {
            sample.kind = .hrv
        } else if isRHRName(typeText) {
            sample.kind = .rhr
        } else {
            sample.kind = hint
        }

        // 再取值
        switch sample.kind {
        case .hrv:
            sample.value = numericValue ?? NumericSampleParser.values(in: valueText).first
        case .rhr:
            sample.value = numericValue ?? NumericSampleParser.values(in: valueText).first
        case .sleep:
            if let start = sample.start, let end = sample.end {
                sample.duration = max(0, end.timeIntervalSince(start))
            } else {
                sample.duration = sleepDuration(dict: dict, start: sample.start, end: sample.end)
            }
        case .unknown:
            if isHRVUnit(unitText) {
                sample.kind = .hrv
                sample.value = numericValue
            } else if isRHRUnit(unitText) {
                sample.kind = .rhr
                sample.value = numericValue
            }
        }

        return sample
    }

    // MARK: - 纯文本逐行处理

    /// 处理一行。
    private static func parseLine(_ text: String, hint: SampleKind) -> [ParsedSample] {
        let isSleepChannel = {
            if case .sleep = hint { return true }
            if case .sleep = kindFromName(text) { return true }
            return false
        }()

        if isSleepChannel {
            let samples = sleepSamples(in: text)
            if !samples.isEmpty { return samples }
        }

        // 数值通道：先找「数值 + 单位」
        let unitHits = unitValueHits(in: text)
        if !unitHits.isEmpty {
            return unitHits.map { hit in
                var sample = ParsedSample()
                sample.raw = text
                sample.kind = hit.kind
                sample.value = hit.value
                return sample
            }
        }

        return fallbackSamples(text, hint: hint)
    }

    /// 睡眠通道：一行里的若干个睡眠分段。
    ///
    /// 优先按分期关键词切；没有关键词就按相邻时间点两两配对。
    private static func sleepSamples(in text: String) -> [ParsedSample] {
        let hits = sleepStageHits(in: text)
        if !hits.isEmpty {
            return sleepSegments(in: text, hits: hits)
        }
        return pairedTimeSegments(in: text)
    }

    /// 睡眠分期的关键词命中位置。
    private struct StageHit {
        var range: NSRange
        var stage: SleepStage
    }

    /// 找出文本里所有睡眠分期关键词。
    private static func sleepStageHits(in text: String) -> [StageHit] {
        let lower = text.lowercased()
        var hits: [StageHit] = []

        for (keyword, stage) in sleepKeywords {
            var searchStart = lower.startIndex
            while searchStart < lower.endIndex {
                guard let found = lower.range(of: keyword, range: searchStart..<lower.endIndex) else { break }
                let location = lower.distance(from: lower.startIndex, to: found.lowerBound)
                hits.append(StageHit(range: NSRange(location: location, length: keyword.count), stage: stage))
                searchStart = found.upperBound
            }
        }

        // 同一段文字被多个关键词命中时，只留最长的那个
        hits.sort { $0.range.length > $1.range.length }
        var unique: [StageHit] = []
        for hit in hits {
            let overlaps = unique.contains { NSIntersectionRange($0.range, hit.range).length > 0 }
            if !overlaps { unique.append(hit) }
        }
        return unique.sorted { $0.range.location < $1.range.location }
    }

    /// 按分期关键词把一行切成若干段。
    ///
    /// 每段 = 「上一个关键词之后」到「下一个关键词之前」，
    /// 这样起止时间无论写在分期词前面还是后面都不会丢。
    ///
    /// 段内的时间点**两两配对**
    /// ----------------------
    /// 一段里可能还藏着**没写分期名**的片段 ——
    /// 比如 Apple 只写「睡眠」而没有「核心睡眠」，那一段就没命中关键词，
    /// 于是它的时间点会落在相邻的命中段里。
    /// 这时如果只取头两个时间点，后面那几段的时长就凭空丢了（总睡眠会偏短）。
    /// 所以改成两两配对：多出来的时间点照样算成段（分期沿用当前这段的），
    /// **总时长一定不丢**，宁可分期粗一点。
    private static func sleepSegments(in text: String, hits: [StageHit]) -> [ParsedSample] {
        let ns = text as NSString
        var samples: [ParsedSample] = []

        for (index, hit) in hits.enumerated() {
            let start = index == 0 ? 0 : hits[index - 1].range.location + hits[index - 1].range.length
            let end = index + 1 < hits.count ? hits[index + 1].range.location : text.count
            guard end > start else { continue }
            let piece = ns.substring(with: NSRange(location: start, length: end - start))

            let moments = extractMoments(piece)
            guard moments.moments.count >= 2 else {
                // 时间点不够 → 只能靠「X 小时 Y 分钟」这种写法
                var sample = ParsedSample()
                sample.raw = piece
                sample.kind = .sleep(hit.stage)
                sample.duration = durationFromText(moments.cleaned)
                samples.append(sample)
                continue
            }

            var cursor = 0
            while cursor + 1 < moments.moments.count {
                let begin = moments.moments[cursor]
                let finish = moments.moments[cursor + 1]
                let duration = durationBetween(begin, finish)
                if duration > 0 {
                    var sample = ParsedSample()
                    sample.raw = piece
                    sample.kind = .sleep(hit.stage)
                    sample.start = begin.date
                    sample.end = finish.date
                    sample.duration = duration
                    samples.append(sample)
                }
                cursor += 2
            }
        }

        return samples
    }

    /// 没有分期关键词时：把相邻的时间点两两配对，当成睡眠分段。
    ///
    /// 这是「快捷指令只给了起止时间、没给分期」时的兜底，
    /// 至少总时长不会丢（分期按「未分期」记，评分时分期分走中性 50）。
    private static func pairedTimeSegments(in text: String) -> [ParsedSample] {
        let moments = extractMoments(text)
        guard moments.moments.count >= 2 else { return [] }

        var samples: [ParsedSample] = []
        for index in 0..<(moments.moments.count - 1) {
            let start = moments.moments[index]
            let end = moments.moments[index + 1]
            let duration = durationBetween(start, end)
            guard duration > 0 else { continue }

            var sample = ParsedSample()
            sample.raw = text
            sample.kind = .sleep(.unspecified)
            sample.start = start.date
            sample.end = end.date
            sample.duration = duration
            samples.append(sample)
        }
        return samples
    }

    /// 兜底：一段文本里认不出单位、也没有分期关键词。
    ///
    /// HRV / 静息心率通道 → 这一行剩下的所有数字，每个算一个样本（后续取中位数/平均）。
    /// 睡眠通道 → 交给调用方按时间配对处理。
    private static func fallbackSamples(_ text: String, hint: SampleKind) -> [ParsedSample] {
        let moments = extractMoments(text)

        // 先看是不是睡眠
        if let stage = SleepStage.detect(text) {
            var sample = ParsedSample()
            sample.raw = text
            sample.kind = .sleep(stage)
            if moments.moments.count >= 2 {
                sample.start = moments.moments[0].date
                sample.end = moments.moments[1].date
                sample.duration = durationBetween(moments.moments[0], moments.moments[1])
            } else {
                sample.duration = durationFromText(moments.cleaned)
            }
            return [sample]
        }

        if let match = firstUnitMatch(in: text) {
            var sample = ParsedSample()
            sample.raw = text
            sample.kind = match.kind
            sample.value = match.value
            return [sample]
        }

        // 指标名定类型
        let kind = kindFromName(text)
        let effectiveKind: SampleKind = {
            if case .unknown = kind { return hint }
            return kind
        }()

        switch effectiveKind {
        case .hrv, .rhr:
            let values = NumericSampleParser.values(in: moments.cleaned)
            if values.isEmpty {
                var sample = ParsedSample()
                sample.raw = text
                sample.kind = .unknown
                return [sample]
            }
            return values.map { value in
                var sample = ParsedSample()
                sample.raw = text
                sample.kind = effectiveKind
                sample.value = value
                return sample
            }
        case .sleep:
            // 睡眠通道但只有一对时间 → 单独一段
            if moments.moments.count >= 2 {
                var sample = ParsedSample()
                sample.raw = text
                sample.kind = .sleep(.unspecified)
                sample.start = moments.moments[0].date
                sample.end = moments.moments[1].date
                sample.duration = durationBetween(moments.moments[0], moments.moments[1])
                return [sample]
            }
            var sample = ParsedSample()
            sample.raw = text
            sample.kind = .sleep(.unspecified)
            sample.duration = durationFromText(moments.cleaned)
            return [sample]
        case .unknown:
            var sample = ParsedSample()
            sample.raw = text
            sample.kind = .unknown
            return [sample]
        }
    }

    // MARK: - 单位与指标名

    /// 「数值 + 单位」的命中。
    private struct UnitHit {
        var kind: SampleKind
        var value: Double?
    }

    /// 找出文本里所有「数值 + 单位」。
    private static func unitValueHits(in text: String) -> [UnitHit] {
        guard let regex = unitValueRegex else { return [] }
        let ns = text as NSString
        var hits: [UnitHit] = []

        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let unit = ns.substring(with: match.range(at: 2)).lowercased()
            let value = Double(ns.substring(with: match.range(at: 1)))
            if isHRVUnit(unit) {
                hits.append(UnitHit(kind: .hrv, value: value))
            } else if isRHRUnit(unit) {
                hits.append(UnitHit(kind: .rhr, value: value))
            }
        }
        return hits
    }

    private static func isHRVUnit(_ unit: String) -> Bool {
        let u = unit.lowercased().replacingOccurrences(of: " ", with: "")
        return u.contains("毫秒") || u == "ms" || u.hasPrefix("ms") || u.contains("millisecond")
    }

    private static func isRHRUnit(_ unit: String) -> Bool {
        let u = unit.lowercased().replacingOccurrences(of: " ", with: "")
        return u.contains("次/分") || u.contains("次每分") || u.contains("次／分") || u.contains("拍/分")
            || u.contains("bpm") || u.contains("count/min") || u.contains("beats/min")
    }

    private static func isHRVName(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("心率变异性") || t.contains("heart rate variability") || t.contains("sdnn") || t.contains("hrv")
    }

    private static func isRHRName(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("静息心率") || t.contains("resting heart rate") || t.contains("rhr")
    }

    private static func isSleepName(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("睡眠分析") || t.contains("sleep analysis")
    }

    /// 从指标名判断类型（认不出就 .unknown）。
    private static func kindFromName(_ text: String) -> SampleKind {
        if isHRVName(text) { return .hrv }
        if isRHRName(text) { return .rhr }
        if isSleepName(text) { return .sleep(.unspecified) }
        return .unknown
    }

    /// 睡眠分期的中英文关键词表。
    private static let sleepKeywords: [(String, SleepStage)] = [
        ("asleepdeep", .deep),
        ("asleeprem", .rem),
        ("asleepcore", .core),
        ("asleepunspecified", .unspecified),
        ("inbed", .inBed),
        ("awake", .awake),
        ("深睡", .deep),
        ("深度睡眠", .deep),
        ("快速眼动", .rem),
        ("核心睡眠", .core),
        ("未分期", .unspecified),
        ("在床", .inBed),
        ("清醒", .awake)
    ]

    /// 匹配「数值 + 单位」。
    private static let unitValueRegex: NSRegularExpression? = {
        let pattern = #"(\d+(?:\.\d+)?)\s*(毫秒|ms|MS|次每分|次/分|次／分|拍/分|bpm|BPM|count/min)"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    private static func firstUnitMatch(in text: String) -> (kind: SampleKind, value: Double?)? {
        let hits = unitValueHits(in: text)
        return hits.first.map { (kind: $0.kind, value: $0.value) }
    }

    // MARK: - 日期与时间

    /// 抽出来的一个时间点。
    ///
    /// `isTimeOnly` 表示它只有「几点几分」，没有日期 ——
    /// 这种情况下算时长要靠「跨零点就加一天」来修正。
    private struct Moment {
        var date: Date
        var isTimeOnly: Bool
    }

    /// 从文本里抽出日期时间，并返回「去掉日期后的干净文本」。
    private static func extractMoments(_ text: String) -> (moments: [Moment], cleaned: String) {
        let ns = text as NSString
        var matches: [MomentMatch] = []
        var occupied: [NSRange] = []

        func append(_ match: MomentMatch) {
            let overlaps = occupied.contains { NSIntersectionRange($0, match.range).length > 0 }
            guard !overlaps else { return }
            matches.append(match)
            occupied.append(match.range)
        }

        // A: 2026-10-27 23:15:00 / 2026年10月27日 23:15
        if let regex = try? NSRegularExpression(pattern: #"(\d{4})\s*[-/.年]\s*(\d{1,2})\s*[-/.月]\s*(\d{1,2})\s*日?(?:\s*[T,，\-–—]?\s*(\d{1,2}):(\d{2})(?::(\d{2}))?)?"#) {
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let year = Int(ns.substring(with: match.range(at: 1)))
                let month = Int(ns.substring(with: match.range(at: 2)))
                let day = Int(ns.substring(with: match.range(at: 3)))
                let hasTime = match.range(at: 4).location != NSNotFound
                let hour = hasTime ? Int(ns.substring(with: match.range(at: 4))) : nil
                let minute = hasTime ? Int(ns.substring(with: match.range(at: 5))) : nil
                let second = (hasTime && match.range(at: 6).location != NSNotFound) ? Int(ns.substring(with: match.range(at: 6))) : nil
                guard let date = makeDate(year: year, month: month, day: day, hour: hour, minute: minute, second: second) else { continue }
                append(MomentMatch(range: match.range, date: date, hasTime: hasTime, timeOnly: false))
            }
        }

        // B: 10月27日 23:15（没有年份，用今年）
        if let regex = try? NSRegularExpression(pattern: #"(\d{1,2})\s*月\s*(\d{1,2})\s*日(?:\s*[T,，\-–—]?\s*(\d{1,2}):(\d{2})(?::(\d{2}))?)?"#) {
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let month = Int(ns.substring(with: match.range(at: 1)))
                let day = Int(ns.substring(with: match.range(at: 2)))
                let hasTime = match.range(at: 3).location != NSNotFound
                let hour = hasTime ? Int(ns.substring(with: match.range(at: 3))) : nil
                let minute = hasTime ? Int(ns.substring(with: match.range(at: 4))) : nil
                let second = (hasTime && match.range(at: 5).location != NSNotFound) ? Int(ns.substring(with: match.range(at: 5))) : nil
                guard let date = makeDate(year: nil, month: month, day: day, hour: hour, minute: minute, second: second) else { continue }
                append(MomentMatch(range: match.range, date: date, hasTime: hasTime, timeOnly: false))
            }
        }

        // C: 单独的时间 08:00:00
        if let regex = try? NSRegularExpression(pattern: #"(?<![\d:])(\d{1,2}):(\d{2})(?::(\d{2}))?(?![\d:])"#) {
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let hour = Int(ns.substring(with: match.range(at: 1)))
                let minute = Int(ns.substring(with: match.range(at: 2)))
                let second = match.range(at: 3).location != NSNotFound ? Int(ns.substring(with: match.range(at: 3))) : nil
                guard let date = makeDate(year: nil, month: nil, day: nil, hour: hour, minute: minute, second: second) else { continue }
                append(MomentMatch(range: match.range, date: date, hasTime: true, timeOnly: true))
            }
        }

        // 时间单独出现时，如果前面紧挨着一个「只有日期」的片段，合并成一个完整时间。
        matches.sort { $0.range.location < $1.range.location }
        var combined: [MomentMatch] = []
        for match in matches {
            if var previous = combined.last {
                if match.timeOnly && !previous.hasTime {
                    let gap = match.range.location - previous.range.location
                    if gap <= 3 {
                        let dateParts = Calendar.current.dateComponents([.year, .month, .day], from: previous.date)
                        let timeParts = Calendar.current.dateComponents([.hour, .minute, .second], from: match.date)
                        if let merged = makeDate(
                            year: dateParts.year,
                            month: dateParts.month,
                            day: dateParts.day,
                            hour: timeParts.hour,
                            minute: timeParts.minute,
                            second: timeParts.second
                        ) {
                            previous.date = merged
                            previous.hasTime = true
                            previous.timeOnly = false
                            previous.range = NSUnionRange(previous.range, match.range)
                            combined[combined.count - 1] = previous
                            continue
                        }
                    }
                }
                combined.append(match)
            } else {
                combined.append(match)
            }
        }

        // 把日期片段抹掉，剩下的才是纯数值文本
        var cleaned = text
        for match in combined.reversed() {
            let nsRange = match.range
            if nsRange.location + nsRange.length <= (cleaned as NSString).length {
                cleaned = (cleaned as NSString).replacingCharacters(in: nsRange, with: " ")
            }
        }

        return (combined.map { Moment(date: $0.date, isTimeOnly: $0.timeOnly) }, cleaned)
    }

    private struct MomentMatch {
        var range: NSRange
        var date: Date
        var hasTime: Bool
        var timeOnly: Bool
    }

    /// 两个时间点之间的时长。
    ///
    /// 睡眠经常跨零点（23:30 → 06:45），只给了「几点几分」的时候
    /// 直接相减会得到负数，所以负数一律补一天。
    private static func durationBetween(_ start: Moment, _ end: Moment) -> TimeInterval {
        let cal = Calendar.current

        if start.isTimeOnly && end.isTimeOnly {
            var seconds = end.date.timeIntervalSince(start.date)
            if seconds < 0 { seconds += 86400 }
            return seconds
        }

        if end.isTimeOnly {
            // 结束只有时分秒 → 用开始那天的日期补上
            let startParts = cal.dateComponents([.year, .month, .day], from: start.date)
            let endParts = cal.dateComponents([.hour, .minute, .second], from: end.date)
            var components = DateComponents()
            components.year = startParts.year
            components.month = startParts.month
            components.day = startParts.day
            components.hour = endParts.hour
            components.minute = endParts.minute
            components.second = endParts.second
            guard let built = cal.date(from: components) else {
                return max(0, end.date.timeIntervalSince(start.date))
            }
            var seconds = built.timeIntervalSince(start.date)
            if seconds < 0 { seconds += 86400 }
            return seconds
        }

        if start.isTimeOnly {
            // 开始只有时分秒 → 用结束那天的日期反推
            let startParts = cal.dateComponents([.hour, .minute, .second], from: start.date)
            let endParts = cal.dateComponents([.year, .month, .day], from: end.date)
            var components = DateComponents()
            components.year = endParts.year
            components.month = endParts.month
            components.day = endParts.day
            components.hour = startParts.hour
            components.minute = startParts.minute
            components.second = startParts.second
            guard let built = cal.date(from: components) else {
                return max(0, end.date.timeIntervalSince(start.date))
            }
            var seconds = end.date.timeIntervalSince(built)
            if seconds < 0 { seconds += 86400 }
            return seconds
        }

        return max(0, end.date.timeIntervalSince(start.date))
    }

    private static func makeDate(
        year: Int?,
        month: Int?,
        day: Int?,
        hour: Int?,
        minute: Int?,
        second: Int?
    ) -> Date? {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = year ?? calendar.component(.year, from: Date())
        if let month = month { components.month = month }
        if let day = day { components.day = day }
        components.hour = hour ?? 0
        components.minute = minute ?? 0
        components.second = second ?? 0
        return calendar.date(from: components)
    }

    // MARK: - 时长

    /// 从「1 小时 20 分」「45 分钟」「120 秒」里认时长。
    private static func durationFromText(_ text: String) -> TimeInterval? {
        let ns = text as NSString
        if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*小时\s*(\d+)?\s*分?"#) {
            if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                let hours = Double(ns.substring(with: match.range(at: 1))) ?? 0
                let minutes = match.range(at: 2).location != NSNotFound ? (Double(ns.substring(with: match.range(at: 2))) ?? 0) : 0
                return hours * 3600 + minutes * 60
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*分(?:钟)?"#) {
            if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                let minutes = Double(ns.substring(with: match.range(at: 1))) ?? 0
                return minutes * 60
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"(\d+)\s*秒"#) {
            if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                let seconds = Double(ns.substring(with: match.range(at: 1))) ?? 0
                return seconds
            }
        }
        return nil
    }

    /// 从 JSON 字典里认时长。
    private static func sleepDuration(dict: [String: Any], start: Date?, end: Date?) -> TimeInterval? {
        if let start = start, let end = end, end > start {
            return end.timeIntervalSince(start)
        }
        for key in ["duration", "时长", "durationinseconds"] {
            if let value = dict[key] {
                if let number = value as? NSNumber { return number.doubleValue }
                if let text = value as? String {
                    if let seconds = Double(text) { return seconds }
                    if let duration = durationFromText(text) { return duration }
                    if let parsed = iso8601Duration(text) { return parsed }
                }
            }
        }
        return nil
    }

    private static func iso8601Duration(_ text: String) -> TimeInterval? {
        let pattern = #"^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else {
            return nil
        }
        let ns = text as NSString
        func value(_ index: Int) -> Double {
            guard match.range(at: index).location != NSNotFound else { return 0 }
            return Double(ns.substring(with: match.range(at: index))) ?? 0
        }
        return value(1) * 3600 + value(2) * 60 + value(3)
    }

    // MARK: - 字典取值

    private static func lookupString(_ dict: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String { return value }
        }
        let lowered = dict.map {
            ($0.key.lowercased().replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " "), $0.value)
        }
        for key in keys {
            let target = key.lowercased()
            for (dictKey, value) in lowered where dictKey == target {
                if let string = value as? String { return string }
            }
        }
        return nil
    }

    private static func lookupNumber(_ dict: [String: Any], _ keys: [String]) -> Double? {
        for key in keys {
            if let number = dict[key] as? NSNumber { return number.doubleValue }
            if let text = dict[key] as? String, let value = Double(text) { return value }
        }
        let lowered = dict.map { ($0.key.lowercased(), $0.value) }
        for key in keys {
            let target = key.lowercased()
            for (dictKey, value) in lowered where dictKey == target {
                if let number = value as? NSNumber { return number.doubleValue }
                if let text = value as? String, let parsed = Double(text) { return parsed }
            }
        }
        return nil
    }

    private static func lookupDate(_ dict: [String: Any], _ keys: [String]) -> Date? {
        for key in keys {
            guard let value = dict[key] else { continue }
            if let date = value as? Date { return date }
            if let number = value as? NSNumber {
                let seconds = number.doubleValue
                if seconds > 1_000_000_000 { return Date(timeIntervalSince1970: seconds) }
                continue
            }
            if let text = value as? String {
                let moments = extractMoments(text)
                if let first = moments.moments.first { return first.date }
            }
        }
        return nil
    }

    /// 把字典拼成一行可读文本，认不出来时给用户看。
    private static func describe(_ dict: [String: Any]) -> String {
        dict.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
    }
}
