import SwiftUI

/// 手动补录某一天的健康数据。
///
/// 为什么需要它
/// ------------
/// 正常路径是「快捷指令 → App Intent」自动喂数据。
/// 但「查找健康记录（睡眠分析）」能不能带上起止时间，取决于用户那条快捷指令
/// 怎么搭 —— 很多人短时间内搭不对（要么只有分期名没有时间，要么类型选错直接报错）。
///
/// 这个页面是**兜底**：照着「健康」App 里看到的数字手填，30 秒录完，
/// 今天的分数立刻就有 —— 睡眠那 35% 的权重不会再缺。
///
/// 数据写进的是**同一个** `ManualHealthStore`，走同一套基线与评分引擎，
/// 而且是「合并」而不是覆盖：手填睡眠不会把快捷指令记的 HRV 抹掉。
struct ManualEntryView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var sleepText = ""
    @State private var deepText = ""
    @State private var remText = ""
    @State private var inBedText = ""
    @State private var hrvText = ""
    @State private var rhrText = ""
    @State private var message: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    hintCard

                    VStack(spacing: 12) {
                        SectionTitle(title: "睡眠", subtitle: "分钟数；「健康」App 里显示的小时记得换算")

                        fieldRow(title: "睡眠时长", unit: "分钟", text: $sleepText, placeholder: "452")
                        fieldRow(title: "深睡", unit: "分钟", text: $deepText, placeholder: "86")
                        fieldRow(title: "REM", unit: "分钟", text: $remText, placeholder: "121")
                        fieldRow(title: "在床", unit: "分钟", text: $inBedText, placeholder: "500")
                    }
                    .cardStyle()

                    VStack(spacing: 12) {
                        SectionTitle(title: "心率", subtitle: "留空表示没填，不会覆盖快捷指令记的值")
                        fieldRow(title: "HRV", unit: "ms", text: $hrvText, placeholder: "57")
                        fieldRow(title: "静息心率", unit: "bpm", text: $rhrText, placeholder: "62")
                    }
                    .cardStyle()

                    if let message {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.warn)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .cardStyle(padding: 14)
                    }

                    previewCard

                    saveButton

                    Text("数据只存在这台手机上（Application Support/FitState/fitstate-manual.json），不联网、不上传。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(Theme.background)
            .scrollIndicators(.hidden)
            .navigationTitle("手动补录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .onAppear(perform: loadExisting)
    }

    // MARK: - 卡片

    private var hintCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(Theme.primary)
                Text("照着「健康」App 手填")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            Text("打开「健康」App → 睡眠，把总时长、深睡、REM 抄过来（分钟）。保存后今天的分数立刻重算，睡眠那 35% 的权重就不会缺。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "保存后这一天的数据")
            HStack(spacing: 18) {
                previewItem(title: "睡眠", value: sleepSummary)
                previewItem(title: "效率", value: efficiencyText)
                previewItem(title: "修复性", value: restorativeText)
            }
        }
        .cardStyle()
    }

    private func previewItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text("保存并重算")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Theme.primary)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 输入行

    private func fieldRow(title: String, unit: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .frame(width: 96)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.hairline.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(unit)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .frame(width: 34, alignment: .leading)
        }
    }

    // MARK: - 取值

    private var sleepMinutes: Double { number(sleepText) ?? 0 }
    private var deepMinutes: Double { number(deepText) ?? 0 }
    private var remMinutes: Double { number(remText) ?? 0 }
    private var inBedMinutes: Double { number(inBedText) ?? 0 }

    private func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        return Double(trimmed)
    }

    private var sleepSummary: String {
        guard sleepMinutes > 0 else { return "—" }
        let total = Int(sleepMinutes.rounded())
        return "\(total / 60)h\(String(format: "%02d", total % 60))m"
    }

    private var efficiencyText: String {
        guard sleepMinutes > 0, inBedMinutes > sleepMinutes else { return "—" }
        return String(format: "%.0f%%", (sleepMinutes / inBedMinutes) * 100)
    }

    private var restorativeText: String {
        guard sleepMinutes > 0, deepMinutes + remMinutes > 0 else { return "—" }
        return String(format: "%.0f%%", ((deepMinutes + remMinutes) / sleepMinutes) * 100)
    }

    // MARK: - 读写

    /// 打开时把这一天已经记好的数据填进来（方便修改，而不是每次从零填）。
    private func loadExisting() {
        guard !loaded else { return }
        loaded = true
        let key = Fmt.dayKey(date)
        guard let record = ManualHealthStore.loadRecords().first(where: { $0.dayKey == key }) else { return }
        if record.totalSleep > 0 { sleepText = String(Int((record.totalSleep / 60).rounded())) }
        if record.deepSleep > 0 { deepText = String(Int((record.deepSleep / 60).rounded())) }
        if record.remSleep > 0 { remText = String(Int((record.remSleep / 60).rounded())) }
        if record.inBed > 0 { inBedText = String(Int((record.inBed / 60).rounded())) }
        if let hrv = record.hrvMS { hrvText = String(Int(hrv.rounded())) }
        if let rhr = record.restingHR { rhrText = String(Int(rhr.rounded())) }
    }

    private func save() {
        let key = Fmt.dayKey(date)
        var problems: [String] = []

        if sleepMinutes > 0 {
            if deepMinutes + remMinutes > sleepMinutes {
                problems.append("深睡 + REM 不能超过睡眠时长")
            }
            if inBedMinutes > 0, inBedMinutes < sleepMinutes {
                problems.append("在床时长不能小于睡眠时长")
            }
        }
        if hrvText.isEmpty == false, let hrv = number(hrvText), !(5...500).contains(hrv) {
            problems.append("HRV 应该在 5–500 ms 之间")
        }
        if rhrText.isEmpty == false, let rhr = number(rhrText), !(25...220).contains(rhr) {
            problems.append("静息心率应该在 25–220 bpm 之间")
        }
        if sleepMinutes <= 0, number(hrvText) == nil, number(rhrText) == nil {
            problems.append("至少填一项")
        }
        if !problems.isEmpty {
            message = problems.joined(separator: "；")
            return
        }

        var record = ManualDayRecord(
            dayKey: key,
            date: Calendar.current.startOfDay(for: date),
            hrvMS: number(hrvText),
            restingHR: number(rhrText),
            totalSleep: sleepMinutes * 60,
            deepSleep: deepMinutes * 60,
            remSleep: remMinutes * 60,
            inBed: inBedMinutes * 60
        )
        // 深睡 + REM 不允许超过总时长（上面已经拦过，这里再兜一次底）
        record.deepSleep = min(record.deepSleep, record.totalSleep)
        record.remSleep = min(record.remSleep, max(0, record.totalSleep - record.deepSleep))

        guard ManualHealthStore.upsertMerging(record) != nil else {
            message = "写入失败，检查一下 App 的存储空间"
            return
        }

        Task {
            await app.refresh()
            dismiss()
        }
    }
}
