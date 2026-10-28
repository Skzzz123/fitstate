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
    /// 这些参数是**文本框**，不是数字框。
    ///
    /// 为什么
    /// ------
    /// 原来是 `Double`。用户把「查找健康记录」的输出接上去时，
    /// 快捷指令会在**调用本 Intent 之前**就抛「无法将文本转换为数字」而中止 ——
    /// Intent 根本没被调起来，App 里一条数据都没有，回执也看不到。
    ///
    /// 现在接什么都不报错。App 会自己判断：
    ///   - 填了纯数字 → 直接用；
    ///   - 填了带单位的一批样本 → 按这个通道取中位数 / 平均；
    ///   - 认不出来（接错通道、时间戳、别的东西）→ **忽略**，并在回执里说明。
    ///
    /// 优先级是**逐项**的：这一项你填了数（> 0）就以你填的为准，
    /// 没填就沿用原始数据通道解析出来的结果。
    /// 所以「只填睡眠时长、其余留空」也能拿到文本里的深睡 / REM 分期。
    @Parameter(title: "HRV(ms)", default: "")
    var hrvMS: String

    @Parameter(title: "静息心率(bpm)", default: "")
    var restingHR: String

    @Parameter(title: "睡眠时长(分钟)", default: "")
    var sleepMinutes: String

    @Parameter(title: "深睡(分钟)", default: "")
    var deepMinutes: String

    @Parameter(title: "REM(分钟)", default: "")
    var remMinutes: String

    @Parameter(title: "在床(分钟)", default: "")
    var inBedMinutes: String

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

        let sleepInput = sleepRawText
        let hrvInput = hrvRawText
        let rhrInput = rhrRawText
        let debugOn = debug != 0

        // 通道实收多少字 —— 失败时**无条件**报出来。
        // 这样回执本身就是证据：「变量是空的」和「格式没认出来」是两回事，
        // 不用猜、不用截图，回执直接告诉你每个通道收了多少。
        let channelReport = "收到 睡眠\(sleepInput.count)字/HRV\(hrvInput.count)字/心率\(rhrInput.count)字"

        // —— 睡眠：先解析原始文本，再让「你填的数字」逐项覆盖
        var totalSleep = 0.0
        var deep = 0.0
        var rem = 0.0
        var inBed = 0.0

        if !IntentValueParser.isBlank(sleepInput) {
            let parsed = HealthTextParser.parse(sleepInput, hint: .sleep(.unspecified))
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
                if HealthTextParser.isStageNameOnly(sleepInput) {
                    diagnostics.append("收到的是「只有分期名、没有起止时间」的短文本 —— 请把睡眠那个「组合文本」的类型改成 JSON")
                }
                diagnostics.append("睡眠原文前 120 字：" + sleepInput.prefix(120))
            }
        }

        // 数值参数逐项优先（填了就以你填的为准，没填的留上面解析出来的）
        // 注意：认不出来**不算错**，只是忽略 —— 接错通道的文本绝不能当成分钟数写进去。
        if let value = IntentValueParser.minutes(from: sleepMinutes) {
            totalSleep = value * 60
            notes.append("睡眠时长用参数 \(Int(value.rounded())) 分")
        } else if !IntentValueParser.isBlank(sleepMinutes) {
            diagnostics.append("睡眠时长(分钟) 参数收到 \(sleepMinutes.count) 字，认不出数字（已忽略）")
        }
        if let value = IntentValueParser.minutes(from: deepMinutes) {
            deep = value * 60
        } else if !IntentValueParser.isBlank(deepMinutes) {
            diagnostics.append("深睡(分钟) 参数收到 \(deepMinutes.count) 字，认不出数字（已忽略）")
        }
        if let value = IntentValueParser.minutes(from: remMinutes) {
            rem = value * 60
        } else if !IntentValueParser.isBlank(remMinutes) {
            diagnostics.append("REM(分钟) 参数收到 \(remMinutes.count) 字，认不出数字（已忽略）")
        }
        if let value = IntentValueParser.minutes(from: inBedMinutes) {
            inBed = value * 60
        } else if !IntentValueParser.isBlank(inBedMinutes) {
            diagnostics.append("在床(分钟) 参数收到 \(inBedMinutes.count) 字，认不出数字（已忽略）")
        }

        // —— HRV：参数优先，其次原始列表取中位数（抗离群）
        var hrvValue: Double? = nil
        if let value = IntentValueParser.metric(from: hrvMS, kind: .hrv) {
            hrvValue = value
            notes.append("HRV 用参数 \(Int(value.rounded()))")
        } else if !IntentValueParser.isBlank(hrvMS) {
            diagnostics.append("HRV(ms) 参数收到 \(hrvMS.count) 字，认不出数值（已忽略）")
        }
        if hrvValue == nil, !IntentValueParser.isBlank(hrvInput) {
            let parsed = HealthTextParser.parse(hrvInput, hint: .hrv)
            let values = parsed.hrvValues.filter { IntentValueParser.hrvRange.contains($0) }
            if !values.isEmpty {
                hrvValue = NumericSampleParser.median(values)
                notes.append("HRV：读到 \(values.count) 个值，取中位数")
                if debugOn {
                    diagnostics.append("HRV 全部值：" + values.map { String(format: "%.0f", $0) }.joined(separator: ", "))
                }
            } else {
                notes.append("HRV 数据没解析出来")
                diagnostics.append("HRV 原文前 120 字：" + hrvInput.prefix(120))
            }
        }

        // —— 静息心率：参数优先，其次原始列表取平均
        var rhrValue: Double? = nil
        if let value = IntentValueParser.metric(from: restingHR, kind: .rhr) {
            rhrValue = value
            notes.append("静息心率用参数 \(Int(value.rounded()))")
        } else if !IntentValueParser.isBlank(restingHR) {
            diagnostics.append("静息心率(bpm) 参数收到 \(restingHR.count) 字，认不出数值（已忽略）")
        }
        if rhrValue == nil, !IntentValueParser.isBlank(rhrInput) {
            let parsed = HealthTextParser.parse(rhrInput, hint: .rhr)
            let values = parsed.rhrValues.filter { IntentValueParser.rhrRange.contains($0) }
            if !values.isEmpty {
                rhrValue = NumericSampleParser.average(values)
                notes.append("静息心率：读到 \(values.count) 个值，取平均")
                if debugOn {
                    diagnostics.append("静息心率全部值：" + values.map { String(format: "%.0f", $0) }.joined(separator: ", "))
                }
            } else {
                notes.append("静息心率数据没解析出来")
                diagnostics.append("静息心率原文前 120 字：" + rhrInput.prefix(120))
            }
        }

        // —— 留档：不管成没成都存一份原文，设置页能直接看到「快捷指令到底送来了什么」
        func savePayload(outcome: String) {
            IntentPayloadStore.save(IntentPayload(
                at: Date(),
                dayKey: resolvedDayKey,
                sleepRaw: sleepInput,
                hrvRaw: hrvInput,
                rhrRaw: rhrInput,
                sleepMinutes: sleepMinutes,
                deepMinutes: deepMinutes,
                remMinutes: remMinutes,
                inBedMinutes: inBedMinutes,
                hrvMS: hrvMS,
                restingHR: restingHR,
                outcome: outcome,
                detail: diagnostics.joined(separator: "｜")
            ))
        }

        // 什么都没读到就别写脏数据
        guard hrvValue != nil || rhrValue != nil || totalSleep > 0 else {
            let reason = notes.isEmpty ? "没有读到任何数据" : notes.joined(separator: "；")
            var detail = [channelReport]
            detail.append(contentsOf: diagnostics)
            // 原文摘要：非空的通道各给 80 字，回执本身就够定位问题
            for (label, text) in [("睡眠", sleepInput), ("HRV", hrvInput), ("心率", rhrInput)]
            where !IntentValueParser.isBlank(text) {
                detail.append("\(label)原文：" + String(text.prefix(debugOn ? 200 : 80)))
            }
            savePayload(outcome: "没记上：\(reason)")
            return .result(dialog: "没记上：\(reason)｜\(detail.joined(separator: "｜"))")
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
            savePayload(outcome: "写入失败")
            return .result(dialog: "写入失败。｜\(channelReport)")
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
        let debugText = (debugOn && !diagnostics.isEmpty) ? "｜" + diagnostics.joined(separator: "｜") : ""
        savePayload(outcome: "已记录 \(stored.dayKey)")
        return .result(dialog: "已记录 \(stored.dayKey)\(sleepText)\(scoreText)｜\(channelReport)\(noteText)\(debugText)")
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
