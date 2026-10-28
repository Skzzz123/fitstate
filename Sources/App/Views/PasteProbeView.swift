import SwiftUI

/// 「粘贴自检台」
///
/// 为什么需要它
/// ------------
/// 「快捷指令」的「查找健康记录」输出格式**没有公开文档**，不同 iOS 版本、
/// 不同「组合文本」类型（JSON / 短文本）出来的东西完全不一样。
///
/// 与其靠猜，不如让 App 自己说：这个自检台把「查找健康记录」的输出粘进来，
/// 立刻告诉你解析出了什么 —— HRV 多少个值、中位数多少，睡眠分成几段、
/// 深睡 REM 各多少分钟，哪些片段没认出来。
///
/// 照着「没认出来的原文」改解析规则，比反复重装 App 快得多。
struct PasteProbeView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var raw: String = ""
    @State private var channel: ProbeChannel = .sleep
    @State private var result: ProbeResult?
    @State private var selfTest: ParserSelfTest.Report?

    enum ProbeChannel: String, CaseIterable, Identifiable {
        case sleep = "睡眠分析"
        case hrv = "心率变异性"
        case rhr = "静息心率"

        var id: String { rawValue }

        var hint: String {
            switch self {
            case .sleep: return "「查找健康记录」选睡眠分析，把组合文本的结果粘进来"
            case .hrv: return "「查找健康记录」选心率变异性 (SDNN)"
            case .rhr: return "「查找健康记录」选静息心率"
            }
        }
    }

    struct ProbeResult {
        var hrvValues: [Double] = []
        var rhrValues: [Double] = []
        var sleep: HealthTextParser.SleepBreakdown = .init()
        var unrecognized: [String] = []

        var isEmpty: Bool {
            hrvValues.isEmpty && rhrValues.isEmpty && sleep.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    channelPicker
                    inputCard
                    if let result {
                        resultCard(result)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Theme.background)
            .scrollIndicators(.hidden)
            .navigationTitle("粘贴自检")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                }
            }
        }
    }

    // MARK: - 通道选择

    private var channelPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "这段是哪个指标", subtitle: "告诉 App 怎么归类，不用它自己猜")

            Picker("通道", selection: $channel) {
                ForEach(ProbeChannel.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: channel) { _, _ in
                result = nil
            }
            Text(channel.hint)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    // MARK: - 输入

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "粘进来", subtitle: "「组合文本」动作的输出，原样贴上就行")

            TextEditor(text: $raw)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )
                .frame(minHeight: 130)
                .onChange(of: raw) { _, _ in
                    result = nil
                }

            HStack(spacing: 10) {
                Button {
                    raw = ""
                    result = nil
                } label: {
                    Text("清空")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.hairline)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    result = runProbe()
                } label: {
                    Text("解析看看")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Button {
                selfTest = ParserSelfTest.run()
            } label: {
                Text(selfTest == nil ? "跑一遍解析器自检" : "再跑一次自检")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Theme.primary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)

            if let selfTest {
                selfTestCard(selfTest)
            }
        }
        .cardStyle()
    }

    /// 解析器自检结果。
    ///
    /// 这些用例覆盖的是「最容易悄悄算错」的地方：
    /// 跨零点的睡眠时段、多个样本取中位数、没有单位时靠通道归类。
    private func selfTestCard(_ report: ParserSelfTest.Report) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(report.allPassed ? "自检全部通过" : "自检有失败项")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(report.allPassed ? Theme.primary : Theme.rose)
                Spacer()
                Text("\(report.passedCount)/\(report.cases.count)")
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }

            ForEach(report.cases, id: \.name) { item in
                HStack(alignment: .top, spacing: 7) {
                    Text(item.passed ? "✓" : "✗")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(item.passed ? Theme.primary : Theme.rose)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.body)
                        Text(item.detail)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - 结果

    private func resultCard(_ result: ProbeResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "解析结果", subtitle: "这就是 App 会写进评分引擎的数值")

            if result.isEmpty {
                Label("什么都没读出来", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.warn)
            }

            if !result.hrvValues.isEmpty {
                metricRow(
                    label: "HRV",
                    value: "\(Int((Stats.median(result.hrvValues) ?? 0).rounded())) ms",
                    detail: "读到 \(result.hrvValues.count) 个值，取中位数 · 全部：\(result.hrvValues.map { String(format: "%.0f", $0) }.joined(separator: ", "))"
                )
            }

            if !result.rhrValues.isEmpty {
                metricRow(
                    label: "静息心率",
                    value: "\(Int((Stats.average(result.rhrValues) ?? 0).rounded())) bpm",
                    detail: "读到 \(result.rhrValues.count) 个值，取平均 · 全部：\(result.rhrValues.map { String(format: "%.0f", $0) }.joined(separator: ", "))"
                )
            }

            if !result.sleep.isEmpty {
                metricRow(
                    label: "睡眠总时长",
                    value: Fmt.duration(result.sleep.totalSleep),
                    detail: sleepDetailText(result.sleep)
                )
            }

            if !result.unrecognized.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("没认出来的片段（\(result.unrecognized.count)）")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.warn)
                    ForEach(Array(result.unrecognized.prefix(6).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if result.unrecognized.count > 6 {
                        Text("……还有 \(result.unrecognized.count - 6) 段")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.top, 2)
            }
        }
        .cardStyle()
    }

    /// 睡眠分段的明细文案。
    ///
    /// 刻意做成普通函数而不是塞在 ViewBuilder 里 ——
    /// ViewBuilder 里 `if` 分支必须产出 View，`append` 返回 Void 会直接编译不过。
    private func sleepDetailText(_ sleep: HealthTextParser.SleepBreakdown) -> String {
        var parts: [String] = ["读到 \(sleep.sampleCount) 段"]
        if sleep.deepSleep > 0 {
            parts.append("深睡 \(Int((sleep.deepSleep / 60).rounded())) 分")
        }
        if sleep.remSleep > 0 {
            parts.append("REM \(Int((sleep.remSleep / 60).rounded())) 分")
        }
        if sleep.coreSleep > 0 {
            parts.append("核心 \(Int((sleep.coreSleep / 60).rounded())) 分")
        }
        if sleep.unspecifiedSleep > 0 {
            parts.append("未分期 \(Int((sleep.unspecifiedSleep / 60).rounded())) 分")
        }
        if sleep.awakeInBed > 0 {
            parts.append("清醒 \(Int((sleep.awakeInBed / 60).rounded())) 分")
        }
        if sleep.inBed > 0 {
            parts.append("在床 \(Int((sleep.inBed / 60).rounded())) 分")
        }
        return parts.joined(separator: " · ")
    }

    private func metricRow(label: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.body)
                Spacer()
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.primary)
            }
            Text(detail)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 解析

    private func runProbe() -> ProbeResult {
        var result = ProbeResult()
        let hint: HealthTextParser.SampleKind
        switch channel {
        case .sleep: hint = .sleep(.unspecified)
        case .hrv: hint = .hrv
        case .rhr: hint = .rhr
        }
        let outcome = HealthTextParser.parse(raw, hint: hint)
        result.hrvValues = outcome.hrvValues
        result.rhrValues = outcome.rhrValues
        result.sleep = outcome.sleep
        result.unrecognized = outcome.unrecognized
        return result
    }
}
