import Foundation

/// 手动数据源：App Intent（快捷指令）写进来的每日健康数据。
///
/// 为什么需要它
/// ------------
/// 免费 Apple 账号拿不到 HealthKit 能力，App 自己读不了「健康」App；
/// 但 **App Intent 不需要任何能力**（不需要 HealthKit、不需要 App Groups、
/// 不需要推送），所以侧载出来的包照样能用。
///
/// 「快捷指令」的动作「查找健康记录」负责读「健康」App，
/// 再把这个 App Intent 调起来，数据就落到 App 本地沙盒里，
/// 喂给**同一套**基线与评分引擎。
///
/// 存储位置：Application Support/FitState/fitstate-manual.json
/// （用 Application Support 而不是 Documents，是不想让这些中间数据
///  出现在「文件」App 的共享目录里，用户自己导出的 CSV 仍然走 Documents。）
struct ManualDayRecord: Codable, Equatable {
    var dayKey: String
    var date: Date
    var hrvMS: Double?
    var restingHR: Double?
    /// 秒
    var totalSleep: TimeInterval = 0
    var deepSleep: TimeInterval = 0
    var remSleep: TimeInterval = 0
    var inBed: TimeInterval = 0
    var updatedAt: Date = Date()

    /// 换算成评分引擎认识的日度指标。
    var metrics: DailyMetrics {
        var m = DailyMetrics(dayKey: dayKey, date: date)
        m.hrvMS = hrvMS
        m.restingHR = restingHR
        m.totalSleep = totalSleep
        m.deepSleep = deepSleep
        m.remSleep = remSleep
        m.coreSleep = max(0, totalSleep - deepSleep - remSleep)
        m.inBed = inBed
        m.awakeInBed = max(0, inBed - totalSleep)
        return m
    }

    /// 一行摘要，给「设置」页核对解析对不对用。
    var describe: String {
        var parts: [String] = []
        parts.append("HRV \(hrvMS.map { String(format: "%.0f", $0) } ?? "—") ms")
        parts.append("静息心率 \(restingHR.map { String(format: "%.0f", $0) } ?? "—") bpm")
        if totalSleep > 0 {
            var text = "睡眠 \(Int((totalSleep / 60).rounded())) 分钟"
            if deepSleep > 0 || remSleep > 0 {
                text += "（深睡 \(Int((deepSleep / 60).rounded())) / REM \(Int((remSleep / 60).rounded()))）"
            }
            parts.append(text)
        } else {
            parts.append("睡眠 —")
        }
        if inBed > 0 {
            parts.append("在床 \(Int((inBed / 60).rounded())) 分钟")
        }
        return parts.joined(separator: " · ")
    }
}

enum ManualHealthStore {

    static let fileName = "fitstate-manual.json"

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("FitState", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    // MARK: - 读写

    static func loadRecords() -> [ManualDayRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let records = try? decoder.decode([ManualDayRecord].self, from: data) else { return [] }
        return records.sorted { $0.dayKey < $1.dayKey }
    }

    static func load() -> [DailyMetrics] {
        loadRecords().map { $0.metrics }
    }

    /// 同一天重复记录时覆盖（而不是追加），这样自动化每天跑一次也不会堆重复行。
    @discardableResult
    static func upsert(_ record: ManualDayRecord) -> Bool {
        var records = loadRecords()
        records.removeAll { $0.dayKey == record.dayKey }
        records.append(record)
        return write(records)
    }

    /// 合并规则（纯函数，方便单测）
    ///
    /// - 新值有（non-nil / > 0）就用新值
    /// - 新值没有就保留旧值
    /// - 睡眠四项整组处理，不混搭
    static func merged(_ new: ManualDayRecord, with old: ManualDayRecord?) -> ManualDayRecord {
        guard let old else { return new }
        var out = new
        if out.hrvMS == nil { out.hrvMS = old.hrvMS }
        if out.restingHR == nil { out.restingHR = old.restingHR }
        if out.totalSleep <= 0 && old.totalSleep > 0 {
            out.totalSleep = old.totalSleep
            out.deepSleep = old.deepSleep
            out.remSleep = old.remSleep
            out.inBed = old.inBed
        }
        return out
    }

    /// 同一天重复记录时**合并**，而不是整条覆盖。
    ///
    /// 为什么必须有这个
    /// ----------------
    /// 快捷指令有三条**互相独立**的通道，任何一条偶发失败（最常见的是
    /// 「查找健康记录(睡眠分析)」当天返回空、或者某条输出格式没认出来）
    /// 都不该把这一天**已经记好的数据抹成 0**。
    /// 30 天基线是靠每天一条攒出来的，抹掉一天基线就偏了，而且用户根本
    /// 不会察觉 —— 屏幕上只是「今天睡眠 0 分钟」。
    ///
    /// 返回真正落盘的那条记录（合并后的），落盘失败返回 nil。
    @discardableResult
    static func upsertMerging(_ record: ManualDayRecord) -> ManualDayRecord? {
        var records = loadRecords()
        let merged = Self.merged(record, with: records.first { $0.dayKey == record.dayKey })
        records.removeAll { $0.dayKey == merged.dayKey }
        records.append(merged)
        guard write(records) else { return nil }
        return merged
    }

    /// 落盘 + 广播
    private static func write(_ records: [ManualDayRecord]) -> Bool {
        var sorted = records
        sorted.sort { $0.dayKey < $1.dayKey }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sorted) else { return false }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return false
        }

        NotificationCenter.default.post(name: .fitStateManualDataChanged, object: nil)
        return true
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

extension Notification.Name {
    /// App Intent 写入新数据后广播，App 收到就重算。
    static let fitStateManualDataChanged = Notification.Name("fitstate.manualDataChanged")
}
