import Foundation

/// 最近一次 App Intent 收到的原始数据（留档）。
///
/// 为什么留档
/// ------------
/// 快捷指令的报错只出现在它自己的界面上，App 里看不见；
/// 而「快捷指令到底送来了什么」是排查数据链的第一手证据。
/// 在本地存一份原文，设置页直接显示 + 一键复制，
/// 就不用再靠截图、靠猜 ——
/// 「变量是空的」和「格式没认出来」是两回事，看一眼原文就知道。
///
/// 只存最近一次，不做历史 —— 这是个自给自用的小工具，
/// 留一份当「现场证据」就够了。
struct IntentPayload: Codable, Equatable {
    var at: Date = Date()
    var dayKey: String = ""
    /// 三个原始数据通道
    var sleepRaw: String = ""
    var hrvRaw: String = ""
    var rhrRaw: String = ""
    /// 六个数值参数（现在是文本框）
    var sleepMinutes: String = ""
    var deepMinutes: String = ""
    var remMinutes: String = ""
    var inBedMinutes: String = ""
    var hrvMS: String = ""
    var restingHR: String = ""
    /// 结果说明
    var outcome: String = ""
    var detail: String = ""

    /// 是不是什么都没送到。
    var isEmpty: Bool {
        [sleepRaw, hrvRaw, rhrRaw, sleepMinutes, deepMinutes, remMinutes, inBedMinutes, hrvMS, restingHR]
            .allSatisfy { IntentValueParser.isBlank($0) }
    }

    /// 拼成一段可读文本（设置页显示 + 复制给排查用）。
    var report: String {
        var lines: [String] = []
        lines.append("时间：\(Fmt.dateTime(at))")
        lines.append("日期：\(dayKey)")
        lines.append("结果：\(outcome)")
        if !detail.isEmpty { lines.append("详情：\(detail)") }
        lines.append("")
        lines.append(contentsOf: [
            section("睡眠原文", sleepRaw),
            section("HRV原文", hrvRaw),
            section("静息心率原文", rhrRaw),
            section("睡眠时长参数", sleepMinutes),
            section("深睡参数", deepMinutes),
            section("REM参数", remMinutes),
            section("在床参数", inBedMinutes),
            section("HRV参数", hrvMS),
            section("静息心率参数", restingHR)
        ])
        return lines.joined(separator: "\n")
    }

    private func section(_ title: String, _ text: String) -> String {
        let body = IntentValueParser.isBlank(text) ? "（空）" : text
        return "── \(title)（\(text.count) 字）──\n\(body)"
    }
}

enum IntentPayloadStore {

    static let fileName = "fitstate-last-payload.json"

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("FitState", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    static func save(_ payload: IntentPayload) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
        // 即使这次没写成数据，也要通知界面刷新（让用户看到原文）
        NotificationCenter.default.post(name: .fitStateManualDataChanged, object: nil)
    }

    static func load() -> IntentPayload? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(IntentPayload.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
