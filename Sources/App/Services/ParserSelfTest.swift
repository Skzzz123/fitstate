import Foundation

/// 解析器的自测用例。
///
/// 为什么不写成 XCTest
/// ------------------
/// 这个项目没有测试 target —— 加一个就要动 `project.yml` 和 CI，
/// 而 CI 每跑一轮要好几分钟。但解析器是**整个 0 元路线的地基**：
/// 解析错了，分数就是错的，而且用户要等重装 App 才能发现。
///
/// 所以把关键用例写成一组纯函数断言，在 App 里跑一次就能知道对不对，
/// 也方便以后改解析规则时确认没把旧行为改坏。
///
/// 运行位置：App 内「设置 → 快捷指令喂数据 → 解析自检」里的自检按钮，
/// 或者由 `SelfTestReport` 在 App 启动时静默执行。
enum ParserSelfTest {

    struct Case {
        var name: String
        var passed: Bool
        var detail: String
    }

    struct Report {
        var cases: [Case] = []
        var passedCount: Int { cases.filter { $0.passed }.count }
        var failedCount: Int { cases.count - passedCount }
        var allPassed: Bool { failedCount == 0 }
    }

    // MARK: - 用例

    /// 跑全部用例。
    static func run() -> Report {
        var report = Report()

        // —— 1. 睡眠：英文分期 + 起止时间
        report.cases.append(check(
            "睡眠英文分期 + 起止时间",
            {
                let text = """
                asleepDeep, 2026-10-26 23:00:00, 2026-10-26 23:30:00
                asleepREM, 2026-10-26 23:30:00, 2026-10-27 01:00:00
                asleepCore, 2026-10-27 01:00:00, 2026-10-27 05:00:00
                """
                let out = HealthTextParser.parse(text, hint: .sleep(.unspecified))
                guard out.sleep.sampleCount == 3 else {
                    return (false, "预期 3 段，实际 \(out.sleep.sampleCount) 段")
                }
                let deep = Int((out.sleep.deepSleep / 60).rounded())
                let rem = Int((out.sleep.remSleep / 60).rounded())
                let core = Int((out.sleep.coreSleep / 60).rounded())
                let total = Int((out.sleep.totalSleep / 60).rounded())
                guard deep == 30, rem == 90, core == 240, total == 360 else {
                    return (false, "深睡 \(deep) / REM \(rem) / 核心 \(core) / 合计 \(total)")
                }
                return (true, "深睡 30 / REM 90 / 核心 240 / 合计 360 分")
            }
        ))

        // —— 2. 睡眠：跨零点（只有时分秒）
        report.cases.append(check(
            "睡眠跨零点（23:30 → 06:45）",
            {
                let text = "asleepCore, 23:30, 06:45"
                let out = HealthTextParser.parse(text, hint: .sleep(.unspecified))
                guard out.sleep.sampleCount == 1 else {
                    return (false, "预期 1 段，实际 \(out.sleep.sampleCount) 段")
                }
                let minutes = Int((out.sleep.totalSleep / 60).rounded())
                // 23:30 → 06:45 跨零点 = 7 小时 15 分 = 435 分
                guard minutes == 435 else {
                    return (false, "实际 \(minutes) 分（应为 435）")
                }
                return (true, "435 分")
            }
        ))

        // —— 3. 睡眠：中文分期
        report.cases.append(check(
            "睡眠中文分期",
            {
                let text = """
                深睡, 2026-10-26 23:00:00, 2026-10-26 23:40:00
                快速眼动, 2026-10-26 23:40:00, 2026-10-27 01:10:00
                清醒, 2026-10-27 01:10:00, 2026-10-27 01:20:00
                """
                let out = HealthTextParser.parse(text, hint: .sleep(.unspecified))
                let deep = Int((out.sleep.deepSleep / 60).rounded())
                let rem = Int((out.sleep.remSleep / 60).rounded())
                let awake = Int((out.sleep.awakeInBed / 60).rounded())
                guard deep == 40, rem == 90, awake == 10 else {
                    return (false, "深睡 \(deep) / REM \(rem) / 清醒 \(awake)")
                }
                return (true, "深睡 40 / REM 90 / 清醒 10 分")
            }
        ))

        // —— 4. 睡眠：没有分期关键词，只有时间点 → 按相邻时间配对
        report.cases.append(check(
            "睡眠无分期关键词 → 按时间配对",
            {
                let text = "2026-10-26 23:00:00, 2026-10-27 02:00:00, 2026-10-27 06:00:00"
                let out = HealthTextParser.parse(text, hint: .sleep(.unspecified))
                let total = Int((out.sleep.totalSleep / 60).rounded())
                // 23:00→02:00 = 180 分，02:00→06:00 = 240 分，合计 420 分
                guard total == 420 else {
                    return (false, "实际 \(total) 分（应为 420）")
                }
                return (true, "420 分")
            }
        ))

        // —— 5. HRV：多个值取中位数
        report.cases.append(check(
            "HRV 多值 → 中位数",
            {
                let text = "40 毫秒, 48 毫秒, 52 毫秒, 200 毫秒"
                let out = HealthTextParser.parse(text, hint: .hrv)
                guard out.hrvValues.count == 4 else {
                    return (false, "读到 \(out.hrvValues.count) 个值")
                }
                let median = Stats.median(out.hrvValues) ?? 0
                guard median == 50 else {
                    return (false, "中位数 \(median)（应为 50）")
                }
                return (true, "4 个值，中位数 50")
            }
        ))

        // —— 6. HRV：没有单位，靠通道归类
        report.cases.append(check(
            "HRV 无单位 → 靠通道归类",
            {
                let text = "40, 48, 52"
                let out = HealthTextParser.parse(text, hint: .hrv)
                guard out.hrvValues.count == 3 else {
                    return (false, "读到 \(out.hrvValues.count) 个值")
                }
                guard out.rhrValues.isEmpty else {
                    return (false, "有 \(out.rhrValues.count) 个值被误判成静息心率")
                }
                let median = Stats.median(out.hrvValues) ?? 0
                guard median == 48 else {
                    return (false, "中位数 \(median)（应为 48）")
                }
                return (true, "3 个值，中位数 48")
            }
        ))

        // —— 7. 静息心率：多个值取平均
        report.cases.append(check(
            "静息心率多值 → 平均",
            {
                let text = "52 次/分, 56 次/分, 60 次/分"
                let out = HealthTextParser.parse(text, hint: .rhr)
                let average = Stats.average(out.rhrValues) ?? 0
                guard out.rhrValues.count == 3, Int(average) == 56 else {
                    return (false, "\(out.rhrValues.count) 个值，平均 \(average)")
                }
                return (true, "3 个值，平均 56")
            }
        ))

        // —— 8. JSON 数组
        report.cases.append(check(
            "JSON 数组输出",
            {
                let text = """
                [{"Type":"心率变异性","Value":48,"Unit":"ms"},
                 {"Type":"静息心率","Value":54,"Unit":"count/min"}]
                """
                let out = HealthTextParser.parse(text, hint: .unknown)
                guard out.hrvValues.count == 1, out.rhrValues.count == 1 else {
                    return (false, "HRV \(out.hrvValues.count) 个 / RHR \(out.rhrValues.count) 个")
                }
                guard out.hrvValues.first == 48, out.rhrValues.first == 54 else {
                    return (false, "HRV \(out.hrvValues.first ?? -1) / RHR \(out.rhrValues.first ?? -1)")
                }
                return (true, "HRV 48 / RHR 54")
            }
        ))

        // —— 9. 混在一起：三个通道各一行，靠单位和关键词分流
        report.cases.append(check(
            "三通道混在一段文本里",
            {
                let text = """
                心率变异性, 48 毫秒
                静息心率, 54 次/分
                asleepDeep, 2026-10-26 23:00:00, 2026-10-26 23:40:00
                """
                let out = HealthTextParser.parse(text, hint: .unknown)
                guard out.hrvValues.count == 1, out.rhrValues.count == 1, out.sleep.sampleCount == 1 else {
                    return (false, "HRV \(out.hrvValues.count) / RHR \(out.rhrValues.count) / 睡眠 \(out.sleep.sampleCount)")
                }
                return (true, "各 1 项")
            }
        ))

        // —— 10. 在床时长
        report.cases.append(check(
            "在床分段",
            {
                let text = "在床, 2026-10-26 22:50:00, 2026-10-27 06:45:00"
                let out = HealthTextParser.parse(text, hint: .sleep(.unspecified))
                let inBed = Int((out.sleep.inBed / 60).rounded())
                guard inBed == 475 else {
                    return (false, "在床 \(inBed) 分（应为 475）")
                }
                return (true, "475 分")
            }
        ))

        // —— 11. 完全认不出来 → 进 unrecognized，不污染数据
        report.cases.append(check(
            "认不出来的片段不污染数据",
            {
                let text = "这是一段完全无关的文字"
                let out = HealthTextParser.parse(text, hint: .hrv)
                guard out.hrvValues.isEmpty else {
                    return (false, "读出了 \(out.hrvValues.count) 个值")
                }
                guard !out.unrecognized.isEmpty else {
                    return (false, "没有记进 unrecognized")
                }
                return (true, "\(out.unrecognized.count) 段进了未识别列表")
            }
        ))

        // —— 12. 时长为 0 的分段不算数
        report.cases.append(check(
            "时长 0 的分段不计入",
            {
                let text = "asleepDeep, 2026-10-26 23:00:00, 2026-10-26 23:00:00"
                let out = HealthTextParser.parse(text, hint: .sleep(.unspecified))
                guard out.sleep.sampleCount == 0 else {
                    return (false, "计入了 \(out.sleep.sampleCount) 段")
                }
                return (true, "0 段")
            }
        ))

        // —— 13. 合并规则：新记录没有睡眠 → 保留旧的那一组
        report.cases.append(check(
            "合并：新数据没睡眠 → 保留旧的",
            {
                let old = ManualDayRecord(
                    dayKey: "2026-10-28", date: Date(), hrvMS: 48, restingHR: 54,
                    totalSleep: 8 * 3600, deepSleep: 90 * 60, remSleep: 120 * 60, inBed: 30600)
                let new = ManualDayRecord(
                    dayKey: "2026-10-28", date: Date(), hrvMS: 50, restingHR: nil,
                    totalSleep: 0, deepSleep: 0, remSleep: 0, inBed: 0)
                let out = ManualHealthStore.merged(new, with: old)
                guard out.totalSleep == old.totalSleep,
                      out.deepSleep == old.deepSleep,
                      out.remSleep == old.remSleep,
                      out.inBed == old.inBed else {
                    return (false, "睡眠被覆盖成 \(Int(out.totalSleep / 60)) 分")
                }
                guard out.restingHR == 54 else {
                    return (false, "静息心率被抹成 \(out.restingHR.map { String(format: "%.0f", $0) } ?? "nil")")
                }
                guard out.hrvMS == 50 else {
                    return (false, "HRV 没更新成新值")
                }
                return (true, "睡眠保留 480 分 / 静息心率保留 54 / HRV 更新为 50")
            }
        ))

        // —— 14. 合并规则：新记录有睡眠 → 整组用新的
        report.cases.append(check(
            "合并：新数据有睡眠 → 整组用新的",
            {
                let old = ManualDayRecord(
                    dayKey: "2026-10-28", date: Date(), hrvMS: 48, restingHR: 54,
                    totalSleep: 8 * 3600, deepSleep: 90 * 60, remSleep: 120 * 60, inBed: 30600)
                let new = ManualDayRecord(
                    dayKey: "2026-10-28", date: Date(), hrvMS: nil, restingHR: 56,
                    totalSleep: 7 * 3600, deepSleep: 60 * 60, remSleep: 90 * 60, inBed: 27000)
                let out = ManualHealthStore.merged(new, with: old)
                guard out.totalSleep == 7 * 3600,
                      out.deepSleep == 60 * 60,
                      out.remSleep == 90 * 60,
                      out.inBed == 27000 else {
                    return (false, "睡眠没整组替换")
                }
                guard out.hrvMS == 48 else {
                    return (false, "HRV 丢了")
                }
                guard out.restingHR == 56 else {
                    return (false, "静息心率没更新")
                }
                return (true, "睡眠整组换成 420 分 / HRV 保留 48 / 静息心率更新 56")
            }
        ))

        return report
    }

    // MARK: - 单个用例

    private static func check(_ name: String, _ body: () -> (Bool, String)) -> Case {
        let result = body()
        return Case(name: name, passed: result.0, detail: result.1)
    }

    /// 一行汇总，给日志用。
    static func summary(_ report: Report) -> String {
        let lines = report.cases.map { item in
            "\(item.passed ? "PASS" : "FAIL") | \(item.name) | \(item.detail)"
        }
        return (["TOTAL | \(report.passedCount)/\(report.cases.count) 通过"] + lines).joined(separator: "\n")
    }
}
