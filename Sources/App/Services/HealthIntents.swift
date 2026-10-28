import AppIntents
import Foundation
import WidgetKit

/// 快捷指令入口：把「查找健康记录」取到的数值写进 FitState。
///
/// 这是 0 元路线的核心
/// ------------------
/// 免费 Apple 账号拿不到 HealthKit 能力，App 自己读不了「健康」App。
/// 但 **App Intent 不需要任何能力**，所以：
///
///   快捷指令自动化：
///     「查找健康记录(HRV)」→ 「查找健康记录(静息心率)」→ 「查找健康记录(睡眠分析)」
///     → 「运行 App Intent：记录今日健康数据」
///
/// 数据落到 App 本地沙盒后，喂给**同一套**基线与评分引擎，
/// 分数、建议、趋势、小组件全都照常出。
///
/// 整个过程没有网络、没有账号、没有 $99。
///
/// 三个原始数据参数是**分通道**的
/// ----------------------------
/// 「查找健康记录」每个动作只会返回一种指标，所以每个通道单独传，
/// App 就不用靠「猜这段是 HRV 还是静息心率」来分类 —— 哪怕输出里
/// 没有任何单位名，靠通道也能正确归类。
struct RecordHealthDayIntent: AppIntent {

    static var title: LocalizedStringResource = "记录今日健康数据"

    static var description = IntentDescription(
        "把「查找健康记录」的结果写进 FitState，用来算今日状态分。不需要任何 Apple 能力。"
    )

    /// 不拉起 App，直接在后台写数据。
    static var openAppWhenRun: Bool = false

    /// 「查找健康记录」选「睡眠分析」的原始输出，整包丢进来即可，
    /// 深睡 / REM / 核心 / 清醒 / 在床 由 App 自己拆，省掉一串筛选求和动作。
    @Parameter(title: "睡眠分析原始数据(可选)", default: "")
    var sleepRawText: String

    /// 「查找健康记录」选「心率变异性」的原始输出。塞进来的话，App 自己取中位数。
    @Parameter(title: "HRV原始数据(可选)", default: "")
    var hrvRawText: String

    /// 「查找健康记录」选「静息心率」的原始输出。塞进来的话，App 自己取平均。
    @Parameter(title: "静息心率原始数据(可选)", default: "")
    var rhrRawText: String

    /// 直接填数字（三个「查找」动作之后用「数学」算好的单值）。
    ///
    /// 优先级是**逐项**的：这一项你填了数（> 0）就以你填的为准，
    /// 没填（0）就沿用原始数据通道解析出来的结果。
    /// 所以「只填睡眠时长、其余留空」也能拿到文本里的深睡 / REM 分期。
    @Parameter(title: "HRV(ms)", default: 0)
    var hrvMS: Double

    @Parameter(title: "静息心率(bpm)", default: 0)
    var restingHR: Double

    @Parameter(title: "睡眠时长(分钟)", default: 0)
    var sleepMinutes: Double

    @Parameter(title: "深睡(分钟)", default: 0)
    var deepMinutes: Double

    @Parameter(title: "REM(分钟)", default: 0)
    var remMinutes: Double

    @Parameter(title: "在床(分钟)", default: 0)
    var inBedMinutes: Double

    /// 留空表示今天。格式 YYYY-MM-DD。
    @Parameter(title: "日期(YYYY-MM-DD，留空=今天)", default: "")
    var day: String

    /// 填 1 会在返回结果里附上完整解析诊断（哪段没认出来、原文长什么样）。
    /// 平时留空即可，排查时打开。
    @Parameter(title: "解析诊断(填1=详细回执)", default: 0)
    var debug: Int

    func perform() async throws -> some IntentResult {
        var notes: [String] = []
        var diagnostics: [String] = []

        // —— 睡眠：先解析原始文本，再让「你填的数字」逐项覆盖
        var totalSleep = 0.0
        var deep = 0.0
        var rem = 0.0
        var inBed = 0.0

        if !sleepRawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parsed = HealthTextParser.parse(sleepRawText, hint: .sleep(.unspecified))
            if parsed.sleep.sampleCount > 0 {
                totalSleep = parsed.sleep.totalSleep
                deep = parsed.sleep.deepSleep
                rem = parsed.sleep.remSleep
                inBed = parsed.sleep.inBed
                notes.append("睡眠：读到 \(parsed.sleep.sampleCount) 段")
                if parsed.sleep.deepSleep == 0 && parsed.sleep.remSleep == 0 {
                    notes.append("没有识别出深睡/REM")
                }
                if !parsed.unrecognized.isEmpty {
                    notes.append("有 \(parsed.unrecognized.count) 段没认出来")
                    diagnostics.append("睡眠未识别片段：" + parsed.unrecognized.prefix(3).joined(separator: " ⏐ "))
                }
            } else {
                notes.append("睡眠数据没解析出来")
                diagnostics.append("睡眠：完全没解析出分段。原文前 120 字：" + sleepRawText.prefix(120))
            }
        }
        // 数字参数逐项优先（填了 > 0 的以你填的为准，没填的留上面的解析结果）
        if sleepMinutes > 0 { totalSleep = sleepMinutes * 60 }
        if deepMinutes > 0 { deep = deepMinutes * 60 }
        if remMinutes > 0 { rem = remMinutes * 60 }
        if inBedMinutes > 0 { inBed = inBedMinutes * 60 }

        // —— HRV：原始列表取中位数（抗离群），否则用单值
        var hrvValue: Double? = nil
        if !hrvRawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parsed = HealthTextParser.parse(hrvRawText, hint: .hrv)
            if !parsed.hrvValues.isEmpty {
                hrvValue = NumericSampleParser.median(parsed.hrvValues)
                notes.append("HRV：读到 \(parsed.hrvValues.count) 个值，取中位数")
                if debug != 0 {
                    diagnostics.append("HRV 全部值：" + parsed.hrvValues.map { String(format: "%.0f", $0) }.joined(separator: ", "))
                }
            } else {
                notes.append("HRV 数据没解析出来")
                diagnostics.append("HRV：没解析出数值。原文前 120 字：" + hrvRawText.prefix(120))
            }
        }
        if hrvMS > 0 { hrvValue = hrvMS }

        // —— 静息心率：原始列表取平均，否则用单值
        var rhrValue: Double? = nil
        if !rhrRawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parsed = HealthTextParser.parse(rhrRawText, hint: .rhr)
            if !parsed.rhrValues.isEmpty {
                rhrValue = NumericSampleParser.average(parsed.rhrValues)
                notes.append("静息心率：读到 \(parsed.rhrValues.count) 个值，取平均")
                if debug != 0 {
                    diagnostics.append("静息心率全部值：" + parsed.rhrValues.map { String(format: "%.0f", $0) }.joined(separator: ", "))
                }
            } else {
                notes.append("静息心率数据没解析出来")
                diagnostics.append("静息心率：没解析出数值。原文前 120 字：" + rhrRawText.prefix(120))
            }
        }
        if restingHR > 0 { rhrValue = restingHR }

        // 什么都没读到就别写脏数据
        guard hrvValue != nil || rhrValue != nil || totalSleep > 0 else {
            let reason = notes.isEmpty ? "没有读到任何数据" : notes.joined(separator: "；")
            let detail = diagnostics.isEmpty ? "" : "｜" + diagnostics.joined(separator: "｜")
            return .result(dialog: "没记上：\(reason)\(detail)")
        }

        let record = ManualDayRecord(
            dayKey: resolvedDayKey,
            date: resolvedDate,
            hrvMS: hrvValue,
            restingHR: rhrValue,
            totalSleep: totalSleep,
            deepSleep: deep,
            remSleep: rem,
            inBed: inBed,
            updatedAt: Date()
        )

        // 合并写入：某条通道偶发失败，不会把这一天**已有**的数据抹成 0
        guard let stored = ManualHealthStore.upsertMerging(record) else {
            return .result(dialog: "写入失败。")
        }

        WidgetCenter.shared.reloadAllTimelines()

        var sleepText = ""
        if stored.totalSleep > 0 {
            sleepText = "，睡眠 \(Int((stored.totalSleep / 60).rounded())) 分钟"
            if stored.deepSleep > 0 || stored.remSleep > 0 {
                sleepText += "（深睡 \(Int((stored.deepSleep / 60).rounded())) / REM \(Int((stored.remSleep / 60).rounded()))）"
            }
        }

        let scoreText = currentScoreText(for: stored)
        let noteText = notes.isEmpty ? "" : "｜" + notes.joined(separator: "；")
        let debugText = (debug != 0 && !diagnostics.isEmpty) ? "｜" + diagnostics.joined(separator: "｜") : ""
        return .result(dialog: "已记录 \(stored.dayKey)\(sleepText)\(scoreText)\(noteText)\(debugText)")
    }

    // MARK: - 私有

    private var resolvedDayKey: String {
        let trimmed = day.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let parsed = ManualDayParser.parse(trimmed) {
            return Fmt.dayKey(parsed)
        }
        return Fmt.dayKey(Date())
    }

    private var resolvedDate: Date {
        let trimmed = day.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let parsed = ManualDayParser.parse(trimmed) {
            return parsed
        }
        return Calendar.current.startOfDay(for: Date())
    }

    /// 顺手把刚记上这一天的分数算出来，回给用户当确认。
    ///
    /// 用的是**刚写进去的那条记录**，不是「库里最后一条」——
    /// 补记昨天的时候「库里最后一条」可能是今天，会算错对象。
    private func currentScoreText(for record: ManualDayRecord) -> String {
        let metrics = ManualHealthStore.load()
        let settings = AppSettings().load()
        let baseline = BaselineEngine.build(
            from: metrics,
            windowDays: settings.baselineWindowDays,
            excluding: record.dayKey
        )
        let result = ScoringEngine.evaluate(today: record.metrics, baseline: baseline, settings: settings)
        guard let score = result.score, let tier = result.tier else { return "" }
        let isToday = record.dayKey == Fmt.dayKey(Date())
        return "，\(isToday ? "今日" : "当日")状态分 \(Int(score.rounded()))（\(tier.label)）"
    }
}

/// 一次性喂一整行的版本：适合「查找健康记录 → 组合文本 → 调用本 Intent」这种串法。
///
/// 文本格式（逗号分隔，顺序固定）：
///   HRV(ms),静息心率(bpm),睡眠时长(分钟),深睡(分钟),REM(分钟),在床(分钟)[,日期]
/// 例：48,54,452,86,121,500,2026-10-27
struct RecordHealthDayFromTextIntent: AppIntent {

    static var title: LocalizedStringResource = "用一行文本记录健康数据"

    static var description = IntentDescription(
        "把一整行逗号分隔的数字写进 FitState。顺序：HRV,静息心率,睡眠时长,深睡,REM,在床（可再跟一个日期）。"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "数据行", default: "")
    var text: String

    func perform() async throws -> some IntentResult {
        let parts = text
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        func number(_ index: Int) -> Double {
            guard index < parts.count else { return 0 }
            return Double(parts[index]) ?? 0
        }

        let dayPart = parts.count > 6 ? parts[6] : ""
        let record = ManualDayRecord(
            dayKey: dayPart.isEmpty ? Fmt.dayKey(Date()) : dayPart,
            date: dayPart.isEmpty
                ? Calendar.current.startOfDay(for: Date())
                : (ManualDayParser.parse(dayPart) ?? Calendar.current.startOfDay(for: Date())),
            hrvMS: number(0) > 0 ? number(0) : nil,
            restingHR: number(1) > 0 ? number(1) : nil,
            totalSleep: max(0, number(2)) * 60,
            deepSleep: max(0, number(3)) * 60,
            remSleep: max(0, number(4)) * 60,
            inBed: max(0, number(5)) * 60,
            updatedAt: Date()
        )

        guard let stored = ManualHealthStore.upsertMerging(record) else {
            return .result(dialog: "写入失败。")
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "已记录 \(stored.dayKey)")
    }
}

/// 解析 YYYY-MM-DD。
enum ManualDayParser {
    static func parse(_ text: String) -> Date? {
        let parts = text.split(separator: "-").map { Int($0) }
        guard parts.count == 3, let year = parts[0], let month = parts[1], let day = parts[2] else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)
    }
}
