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
struct RecordHealthDayIntent: AppIntent {

    static var title: LocalizedStringResource = "记录今日健康数据"

    static var description = IntentDescription(
        "把「查找健康记录」的结果写进 FitState，用来算今日状态分。不需要任何 Apple 能力。"
    )

    /// 不拉起 App，直接在后台写数据。
    static var openAppWhenRun: Bool = false

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

    /// 「查找健康记录」选「睡眠分析」的原始输出，整包丢进来即可，
    /// 深睡 / REM / 核心 / 清醒 / 在床 由 App 自己拆，省掉一串筛选求和动作。
    @Parameter(title: "睡眠分析原始数据(可选)", default: "")
    var sleepRawText: String

    func perform() async throws -> some IntentResult {
        // 优先用原始睡眠数据；解析不出来才退回上面几个数字。
        var totalSleepMinutes = max(0, sleepMinutes)
        var deepMinutesValue = max(0, deepMinutes)
        var remMinutesValue = max(0, remMinutes)
        var inBedMinutesValue = max(0, inBedMinutes)

        let parsed = SleepSampleParser.parse(sleepRawText)
        if !parsed.isEmpty {
            totalSleepMinutes = (parsed.asleep / 60).rounded()
            deepMinutesValue = (parsed.deepSleep / 60).rounded()
            remMinutesValue = (parsed.remSleep / 60).rounded()
            if parsed.inBed > 0 {
                inBedMinutesValue = (parsed.inBed / 60).rounded()
            }
        }

        let record = ManualDayRecord(
            dayKey: resolvedDayKey,
            date: resolvedDate,
            hrvMS: hrvMS > 0 ? hrvMS : nil,
            restingHR: restingHR > 0 ? restingHR : nil,
            totalSleep: totalSleepMinutes * 60,
            deepSleep: deepMinutesValue * 60,
            remSleep: remMinutesValue * 60,
            inBed: inBedMinutesValue * 60,
            updatedAt: Date()
        )

        guard ManualHealthStore.upsert(record) else {
            return .result(dialog: "写入失败。")
        }

        WidgetCenter.shared.reloadAllTimelines()

        var sleepText = ""
        if record.totalSleep > 0 {
            sleepText = "，睡眠 \(Int((record.totalSleep / 60).rounded())) 分钟"
            if record.deepSleep > 0 || record.remSleep > 0 {
                sleepText += "（深睡 \(Int((record.deepSleep / 60).rounded())) / REM \(Int((record.remSleep / 60).rounded()))）"
            }
        }

        let scoreText = currentScoreText()
        return .result(dialog: "已记录 \(record.dayKey)\(sleepText)\(scoreText)")
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

    /// 顺手把今天的分数算出来，回给用户当确认。
    private func currentScoreText() -> String {
        let metrics = ManualHealthStore.load()
        guard let today = metrics.last else { return "" }
        let settings = AppSettings().load()
        let baseline = BaselineEngine.build(
            from: metrics,
            windowDays: settings.baselineWindowDays,
            excluding: today.dayKey
        )
        let result = ScoringEngine.evaluate(today: today, baseline: baseline, settings: settings)
        guard let score = result.score, let tier = result.tier else { return "" }
        return "，今日状态分 \(Int(score.rounded()))（\(tier.label)）"
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

        guard ManualHealthStore.upsert(record) else {
            return .result(dialog: "写入失败。")
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "已记录 \(record.dayKey)")
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
