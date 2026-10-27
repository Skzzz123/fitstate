import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @State private var exportURL: URL?
    @State private var showClearConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                permissionSection
                goalSection
                baselineSection
                dataSection
                aboutSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Theme.background)
        .scrollIndicators(.hidden)
        .confirmationDialog("清空小组件缓存？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                SnapshotStore.clear()
            }
            Button("取消", role: .cancel) {}
        }
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

            Text("读取项：睡眠分析（含分期）、HRV (SDNN)、静息心率、训练记录。")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
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
