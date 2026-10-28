import SwiftUI
import UIKit
import Combine

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @State private var exportURL: URL?
    @State private var showClearConfirm = false
    @State private var showProbe = false
    @State private var payload: IntentPayload?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                permissionSection
                shortcutSection
                goalSection
                baselineSection
                dataSection
                importSection
                aboutSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Theme.background)
        .scrollIndicators(.hidden)
        .onAppear { loadPayload() }
        .onReceive(NotificationCenter.default.publisher(for: .fitStateManualDataChanged)) { _ in
            loadPayload()
        }
        .confirmationDialog("清空小组件缓存？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                SnapshotStore.clear()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func loadPayload() {
        payload = IntentPayloadStore.load()
    }

    // MARK: - 权限

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "健康数据权限", subtitle: "只读，不写入任何数据")

            HStack {
                Text("状态")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.body)
                Spacer()
                Text(app.authorization.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(app.authorization == .unknown ? Theme.primary : Theme.warn)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background((app.authorization == .unknown ? Theme.primary : Theme.warn).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            HStack {
                Text("数据来源")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.body)
                Spacer()
                Text(app.dataSource.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(app.dataSource == .none ? Theme.muted : Theme.primary)
            }

            Text("读取项：睡眠分析（含分期）、HRV (SDNN)、静息心率、训练记录。")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if app.authorization == .notSupported {
                Text(HealthKitAvailability.reasonText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if app.usingImportedData {
                Text("当前显示的是 CSV 导入的数据，不是「健康」App 里的数据。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if app.authorization != .notSupported {
                    Button {
                        Task { await app.requestAuthorization() }
                    } label: {
                        Text("重新授权")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Theme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.primary.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("系统设置")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.hairline)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }

    // MARK: - 快捷指令

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "快捷指令喂数据", subtitle: "不需要 HealthKit 能力，0 元就能用")

            HStack {
                Text("已记录")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.body)
                Spacer()
                Text(app.manualDays > 0 ? "\(app.manualDays) 天" : "还没有数据")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(app.manualDays > 0 ? Theme.primary : Theme.muted)
            }

            if let last = app.latestManualRecord {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近一次：\(last.dayKey)")
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(Theme.body)
                    Text(last.describe)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let payload = payload {
                Divider().overlay(Theme.hairline)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("最近一次收到的原文")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.body)
                        Spacer()
                        Text(Fmt.dateTime(payload.at))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                    }

                    Text("结果：\(payload.outcome)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(String(payload.report.prefix(700)))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("这是快捷指令真正送进 App 的内容。数字对不上、格式认不出来，看这里最直接。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        UIPasteboard.general.string = payload.report
                        app.errorMessage = "原文已复制，粘贴给我就行"
                    } label: {
                        Text("复制原文")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Theme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.primary.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("① 打开「快捷指令」→ 新建 → 搜索「查找健康记录」→ 选「心率变异性 (SDNN)」\n② 再加一个「查找健康记录」→ 选「静息心率」\n③ 再加一个「查找健康记录」→ 选「睡眠分析」（开始日期改成「昨天」，否则漏掉昨晚）\n④ 每个「查找」后面加一个「组合文本」，把它的输出接进去（格式选「短文本」就行）\n⑤ 加一个「运行 App」动作 → 选 FitState 的「记录今日健康数据」，把三段文本分别接到「HRV原始数据」「静息心率原始数据」「睡眠分析原始数据」\n⑥ 后面那 6 个数字参数（HRV(ms) 之类）现在是**文本框**：留空即可。接错了也只会忽略并写在回执里，不会把数据搞坏\n⑦ 顶部点「自动化」→ 新建 → 时间「每天早上 7:00」→ 依次选刚才的动作")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.body)
                .fixedSize(horizontal: false, vertical: true)

            Text("❗ 中间绝对不要加「从合并后的文本获取数字」这一步 —— 它会把文本变成数字列表，睡眠分期和起止时间全丢掉。")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.warn)
                .fixedSize(horizontal: false, vertical: true)

            Text("跑完之后回到这个 App，下拉刷新就能看到分数。数据只写在这台 iPhone 里。")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    Task { await app.refresh() }
                } label: {
                    Text("重新读取")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.primary.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    UIPasteboard.general.string = shortcutTemplate
                    app.errorMessage = "模板已复制到剪贴板"
                } label: {
                    Text("复制模板")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.hairline)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Divider().overlay(Theme.hairline)

            Text("卡住了？先用「粘贴自检」看看 App 能不能读懂你那边的输出格式")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showProbe = true
            } label: {
                Text("打开粘贴自检")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
        .sheet(isPresented: $showProbe) {
            PasteProbeView()
                .environmentObject(app)
        }
    }

    /// 给「用一行文本记录健康数据」这个 App Intent 用的模板。
    private var shortcutTemplate: String {
        "48,54,452,86,121,500"
    }

    // MARK: - 目标睡眠

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "目标睡眠时长", subtitle: "按时长给分时的参照系")

            HStack {
                Text("目标")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.body)
                Spacer()
                Text(Fmt.duration(TimeInterval(app.settings.sleepGoalMinutes) * 60))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.ink)
            }

            Slider(
                value: Binding(
                    get: { Double(app.settings.sleepGoalMinutes) },
                    set: { app.settings.sleepGoalMinutes = Int(($0 / 15).rounded() * 15) }
                ),
                in: 300...600,
                step: 15
            )
            .tint(Theme.primary)

            HStack {
                Text("5h")
                Spacer()
                Text("10h")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Theme.muted)
        }
        .cardStyle()
    }

    // MARK: - 基线窗口

    private var baselineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "基线窗口", subtitle: "用多少天的历史来做对比参照")

            Picker("基线窗口", selection: Binding(
                get: { app.settings.baselineWindowDays },
                set: {
                    app.settings.baselineWindowDays = $0
                    Task { await app.refresh() }
                }
            )) {
                ForEach(AppSettings.baselineWindows, id: \.self) { days in
                    Text("\(days) 天").tag(days)
                }
            }
            .pickerStyle(.segmented)

            Text("当前基线：\(app.baseline.progressText)。至少需要 \(Baseline.minimumSamples) 天有效数据，分数才比较可信。")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    // MARK: - 数据

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "数据", subtitle: "全部保存在本机，可随时导出")

            HStack(spacing: 10) {
                Button {
                    exportURL = makeExport()
                } label: {
                    Text("生成 CSV")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.primary.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Text("分享")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                showClearConfirm = true
            } label: {
                Text("清空小组件缓存")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.rose)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.rose.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
    }

    // MARK: - 备用数据源

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "备用数据源", subtitle: "HealthKit 读不到时的兜底：CSV")

            HStack {
                Text("导入文件")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.body)
                Spacer()
                Text(app.importedDays > 0 ? "已载入 \(app.importedDays) 天" : (ImportedHealthStore.exists ? "文件里没有可用数据" : "未找到"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(app.importedDays > 0 ? Theme.primary : Theme.muted)
            }

            Text("把 CSV 放进本 App 的「文件」目录：iPhone 上用「文件」App → 我的 iPhone → 状态；Windows 上用 iTunes 的文件共享拖进去。文件名固定为 \(ImportedHealthStore.fileName)，列依次是 日期,HRV(ms),静息心率(bpm),睡眠时长(min),深睡(min),REM(min),在床(min)。")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = ImportedHealthStore.template
                    app.errorMessage = "模板已复制到剪贴板"
                } label: {
                    Text("复制模板")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.primary.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    Task { await app.refresh() }
                } label: {
                    Text("重新读取")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.hairline)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }

    // MARK: - 关于

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "关于")
            Text("状态 · 只给自己用的训练准备度工具。无账号、无网络、无追踪，所有数据留在 iPhone 里。")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("App Group")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(AppGroup.identifier)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.top, 4)

            HStack {
                Text("共享容器")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(AppGroup.isAvailable ? "可用" : "不可用（小组件无数据）")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppGroup.isAvailable ? Theme.primary : Theme.rose)
            }

            HStack {
                Text("Bundle ID")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(Bundle.main.bundleIdentifier ?? "-")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack {
                Text("版本")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(Bundle.main.appVersion)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
        }
        .cardStyle()
    }

    private func makeExport() -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fitstate-\(Fmt.dayKey(Date())).csv")
        do {
            try app.exportCSV().write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            app.errorMessage = "导出失败：\(error.localizedDescription)"
            return nil
        }
    }
}

extension Bundle {
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
