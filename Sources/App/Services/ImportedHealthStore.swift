import Foundation

/// 备用数据源：从 App 自己的 Documents 目录读一份 CSV。
///
/// 什么时候用得上：万一 HealthKit 那条路始终拿不到授权（老设备、免费账号没开成能力），
/// 还能用「快捷指令」把健康数据导成 CSV 丢进 App 目录，App 会把 CSV 当成
/// HealthKit 的替代来源，喂给**同一套**基线与评分引擎。
///
/// CSV 按**表头名字**匹配列，多余的列直接忽略，所以本 App 自己导出的 CSV 也能再导回来。
/// 需要这几列：
///   日期,HRV(ms),静息心率(bpm),睡眠时长(min),深睡(min),REM(min),在床(min)
/// 「日期」形如 2026-10-27；分钟数是分钟，秒数会被换算好。
enum ImportedHealthStore {

    static let fileName = "fitstate-import.csv"

    /// 给用户照抄的模板（表头 + 一行示例）
    static let template = """
    日期,HRV(ms),静息心率(bpm),睡眠时长(min),深睡(min),REM(min),在床(min)
    2026-10-27,48,54,452,86,121,500
    """

    static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    static func load() -> [DailyMetrics] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return parse(text)
    }

    static func parse(_ text: String) -> [DailyMetrics] {
        let lines = text.split(whereSeparator: { $0.isNewline }).map(String.init)
        guard let header = lines.first else { return [] }

        let columns = header
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        func index(of names: [String]) -> Int? {
            for name in names {
                if let found = columns.firstIndex(of: name) { return found }
            }
            return nil
        }

        let dateIndex = index(of: ["日期", "date", "Date"])
        let hrvIndex = index(of: ["HRV(ms)", "HRV", "hrv"])
        let rhrIndex = index(of: ["静息心率(bpm)", "静息心率", "RHR", "rhr"])
        let sleepIndex = index(of: ["睡眠时长(min)", "睡眠时长", "sleep"])
        let deepIndex = index(of: ["深睡(min)", "深睡", "deep"])
        let remIndex = index(of: ["REM(min)", "REM", "rem"])
        let inBedIndex = index(of: ["在床(min)", "在床", "inBed"])

        guard let dateIndex else { return [] }

        var result: [DailyMetrics] = []
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let fields = line
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count > dateIndex else { continue }
            guard let date = parseDay(fields[dateIndex]) else { continue }

            var metrics = DailyMetrics(dayKey: fields[dateIndex], date: date)
            metrics.hrvMS = number(fields, hrvIndex)
            metrics.restingHR = number(fields, rhrIndex)

            let sleepMinutes = number(fields, sleepIndex) ?? 0
            metrics.totalSleep = sleepMinutes * 60
            metrics.deepSleep = (number(fields, deepIndex) ?? 0) * 60
            metrics.remSleep = (number(fields, remIndex) ?? 0) * 60
            metrics.coreSleep = max(0, metrics.totalSleep - metrics.deepSleep - metrics.remSleep)

            let inBedMinutes = number(fields, inBedIndex) ?? 0
            metrics.inBed = inBedMinutes * 60
            metrics.awakeInBed = max(0, metrics.inBed - metrics.totalSleep)

            result.append(metrics)
        }
        return result.sorted { $0.dayKey < $1.dayKey }
    }

    private static func number(_ fields: [String], _ index: Int?) -> Double? {
        guard let index, index < fields.count else { return nil }
        let text = fields[index]
        if text.isEmpty { return nil }
        return Double(text)
    }

    private static func parseDay(_ text: String) -> Date? {
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
