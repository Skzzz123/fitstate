import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var app: AppState
    @State private var showDetail = false
    @State private var showManualEntry = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                if app.authorization == .shouldRequest || app.authorization == .notDetermined {
                    permissionCard
                }

                if app.authorization == .notSupported {
                    shortcutCard
                }

                scoreCard

                if let breakdown = app.breakdown {
                    dimensionsSection(breakdown)
                }

                workoutsCard

                refreshFooter
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Theme.background)
        .scrollIndicators(.hidden)
        .refreshable {
            await app.refresh()
        }
        .sheet(isPresented: $showManualEntry) {
            ManualEntryView()
                .environmentObject(app)
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.friendlyDay(Date()))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Text("今天状态")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
            Button {
                showManualEntry = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.pencil").font(.system(size: 10.5))
                    Text("补录").font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(Theme.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Theme.primary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            Text(app.baseline.progressText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Theme.hairline)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }

    // MARK: - 授权

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "heart.text.square")
                    .foregroundStyle(Theme.primary)
                Text("需要读取健康数据")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            Text("状态 App 只会读取你的睡眠、HRV、静息心率和训练记录，不会写入任何内容，所有数据都留在本机。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.body)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await app.requestAuthorization() }
            } label: {
                Text("去授权")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
    }

    // MARK: - 快捷指令引导

    /// 免费账号拿不到 HealthKit 能力时的引导：改用「快捷指令」喂数据。
    private var shortcutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(Theme.primary)
                Text("用「快捷指令」把数据喂进来")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            Text("这个安装包没有 HealthKit 能力（免费账号限制），App 自己读不了「健康」。用「快捷指令」的「查找健康记录」取到数，再调用 App 的「记录今日健康数据」动作，数据就会进来，分数、建议、趋势照常算。详细步骤在「设置」页。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.body)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await app.refresh() }
            } label: {
                Text("重新读取")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                showManualEntry = true
            } label: {
                Text("手动补录今天的数字")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.primary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
    }

    // MARK: - 分数卡

    private var scoreCard: some View {
        VStack(spacing: 12) {
            ScoreRing(
                score: app.todayScore,
                size: 168,
                lineWidth: 13,
                caption: app.tier.map { "\($0.label) · \($0.advice)" } ?? nil
            )
            .padding(.top, 4)

            if let breakdown = app.breakdown {
                Text(breakdown.headline)
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(breakdown.advice)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)

                if !breakdown.missing.isEmpty {
                    Text("缺少 \(breakdown.missing.map { $0.label }.joined(separator: "、")) 数据，权重已重新归一化")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 20)
    }

    // MARK: - 分维度明细

    private func dimensionsSection(_ breakdown: ScoreBreakdown) -> some View {
        VStack(spacing: 12) {
            SectionTitle(
                title: breakdown.hasScore ? "为什么是 \(String(format: "%.0f", breakdown.score ?? 0)) 分" : "分维度明细",
                subtitle: "展开每一项，看它对总分贡献了多少"
            )

            ForEach(breakdown.sortedDimensions) { dimension in
                MetricRowView(dimension: dimension, totalWeight: breakdown.score ?? 0)
            }

            HStack {
                Text("总分 = 50 + 各维度贡献之和")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Spacer()
                if let last = app.lastUpdated {
                    Text("更新于 \(last.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - 训练记录

    private var workoutsCard: some View {
        Group {
            if !app.todayWorkouts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "今天的训练", subtitle: "从「健康」读取，仅供趋势关联")
                    ForEach(app.todayWorkouts) { workout in
                        HStack {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.primary)
                            Text(workout.displayName)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text(Fmt.duration(workout.duration))
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                            if let energy = workout.energyKcal {
                                Text("\(Int(energy.rounded())) kcal")
                                    .font(.system(size: 12.5, design: .monospaced))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 66, alignment: .trailing)
                            }
                        }
                    }
                }
                .cardStyle()
            }
        }
    }

    private var refreshFooter: some View {
        Button {
            Task { await app.refresh() }
        } label: {
            HStack(spacing: 7) {
                if app.isLoading {
                    ProgressView().controlSize(.small).tint(Theme.muted)
                } else {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12))
                }
                Text(app.isLoading ? "读取中…" : "重新读取健康数据")
                    .font(.system(size: 13))
            }
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(app.isLoading)
    }
}

/// 单个维度明细行
struct MetricRowView: View {
    let dimension: DimensionScore
    let totalWeight: Double

    private var tint: Color {
        if dimension.score >= 70 { return Theme.primary }
        if dimension.score >= 55 { return Theme.warn }
        return Theme.rose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 7) {
                    Text(dimension.label)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    if dimension.isDrag {
                        Text("拖累项")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Theme.rose)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.rose.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
                Spacer()
                Text(String(format: "%.0f", dimension.score))
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(Theme.ink)
            }

            ScoreBar(value: dimension.score, tint: tint)

            HStack(alignment: .top, spacing: 10) {
                detailColumn(title: "今天", value: dimension.todayText)
                detailColumn(title: "基线", value: dimension.baselineText)
            }

            HStack {
                Text(dimension.deltaText)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(dimension.isDrag ? Theme.rose : Theme.primary)
                Spacer()
                Text(contributionText)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(dimension.contribution >= 0 ? Theme.primary : Theme.rose)
            }
        }
        .cardStyle(padding: 16)
    }

    private var contributionText: String {
        String(format: "贡献 %+.1f", dimension.contribution)
    }

    private func detailColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
