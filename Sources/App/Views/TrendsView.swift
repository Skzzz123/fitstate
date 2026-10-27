import Charts
import SwiftUI

struct TrendsView: View {
    @EnvironmentObject private var app: AppState
    @State private var range = 30

    private var points: [TrendPoint] {
        Array(app.points.suffix(range)).sorted { $0.date < $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                rangePicker

                if points.isEmpty {
                    emptyState
                } else {
                    scoreChart
                    hrvChart
                    sleepChart
                    scatterChart
                    insightsSection
                }
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
    }

    // MARK: - 区间选择

    private var rangePicker: some View {
        HStack(spacing: 6) {
            ForEach([7, 30, 60], id: \.self) { value in
                Button {
                    range = value
                } label: {
                    Text(value == 7 ? "周" : (value == 30 ? "月" : "季"))
                        .font(.system(size: 13, weight: range == value ? .semibold : .regular))
                        .foregroundStyle(range == value ? Color.white : Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(range == value ? Theme.ink : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.hairline)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 28))
                .foregroundStyle(Theme.muted)
            Text("还没有足够的数据")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("连续戴表几天，这里就会出现你的睡眠、HRV 和状态分曲线。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .cardStyle()
    }

    // MARK: - 状态分

    private var scoreChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "状态分", subtitle: "\(points.count) 天 · 颜色代表分档")

            Chart {
                ForEach(points) { point in
                    if let score = point.score {
                        LineMark(
                            x: .value("日期", point.date, unit: .day),
                            y: .value("状态分", score)
                        )
                        .foregroundStyle(Theme.primary)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("日期", point.date, unit: .day),
                            y: .value("状态分", score)
                        )
                        .foregroundStyle(Theme.scoreColor(score))
                        .symbolSize(34)
                    }
                }
            }
            .chartYScale(domain: 20...100)
            .chartYAxis {
                AxisMarks(values: [40.0, 55.0, 70.0, 85.0]) { value in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(String(format: "%.0f", number))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            .chartXAxis {
                dateAxis
            }
            .frame(height: 190)
        }
        .cardStyle()
    }

    // MARK: - HRV

    private var hrvChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "HRV", subtitle: "阴影为基线中间 50% 的区间")

            Chart {
                ForEach(points) { point in
                    if let hrv = point.hrvMS {
                        AreaMark(
                            x: .value("日期", point.date, unit: .day),
                            yStart: .value("下限", app.baseline.hrvP25 ?? 0),
                            yEnd: .value("上限", app.baseline.hrvP75 ?? 0)
                        )
                        .foregroundStyle(Theme.primary.opacity(0.10))

                        LineMark(
                            x: .value("日期", point.date, unit: .day),
                            y: .value("HRV", hrv)
                        )
                        .foregroundStyle(Theme.primary)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("日期", point.date, unit: .day),
                            y: .value("HRV", hrv)
                        )
                        .foregroundStyle(Theme.primary)
                        .symbolSize(22)
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(String(format: "%.0f", number))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            .chartXAxis {
                dateAxis
            }
            .frame(height: 160)
        }
        .cardStyle()
    }

    // MARK: - 睡眠

    private var sleepChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "睡眠时长", subtitle: "深睡部分用深色叠加")

            Chart {
                ForEach(points) { point in
                    if let sleep = point.sleepSeconds {
                        BarMark(
                            x: .value("日期", point.date, unit: .day),
                            y: .value("睡眠", sleep / 3600)
                        )
                        .foregroundStyle(Theme.primary.opacity(0.28))

                        if let deep = point.deepSeconds, deep > 0 {
                            BarMark(
                                x: .value("日期", point.date, unit: .day),
                                y: .value("深睡", deep / 3600)
                            )
                            .foregroundStyle(Theme.primary)
                        }
                    }
                }
            }
            .chartYScale(domain: 0...12)
            .chartYAxis {
                AxisMarks(values: [0.0, 4.0, 8.0, 12.0]) { value in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(String(format: "%.0fh", number))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            .chartXAxis {
                dateAxis
            }
            .frame(height: 160)
        }
        .cardStyle()
    }

    // MARK: - 散点

    private var scatterChart: some View {
        let items = InsightEngine.sleepVsNextDayHRV(points: points).enumerated().map { index, pair in
            ScatterItem(id: index, sleep: pair.sleep, delta: pair.delta)
        }

        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "睡眠时长 vs 次日 HRV 变化", subtitle: "每个点代表一晚")

            if items.isEmpty {
                Text("数据还不足以画出这张图")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                Chart(items) { item in
                    PointMark(
                        x: .value("睡眠时长", item.sleep),
                        y: .value("HRV 变化", item.delta * 100)
                    )
                    .foregroundStyle(item.delta >= 0 ? Theme.primary : Theme.warn)
                    .symbolSize(50)
                }
                .chartXAxis {
                    AxisMarks(values: [5.0, 6.0, 7.0, 8.0, 9.0]) { value in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(String(format: "%.0fh", number))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(String(format: "%.0f%%", number))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
                .frame(height: 170)
            }
        }
        .cardStyle()
    }

    // MARK: - 洞察

    private var insightsSection: some View {
        VStack(spacing: 12) {
            SectionTitle(title: "关于你的发现", subtitle: "基于你自己的数据，不是通用建议")
            ForEach(app.insights) { insight in
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: iconName(for: insight.kind))
                        .font(.system(size: 13))
                        .foregroundStyle(tint(for: insight.kind))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(insight.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(insight.detail)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .cardStyle(padding: 16)
            }
        }
    }

    // MARK: - 坐标轴

    private var dateAxis: some View {
        AxisMarks { value in
            AxisValueLabel {
                if let date = value.as(Date.self) {
                    Text(date.formatted(.dateTime.month(.defaultDigits).day()))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func iconName(for kind: Insight.Kind) -> String {
        switch kind {
        case .finding: return "lightbulb"
        case .warning: return "exclamationmark.triangle"
        case .neutral: return "chart.line.uptrend.xyaxis"
        }
    }

    private func tint(for kind: Insight.Kind) -> Color {
        switch kind {
        case .finding: return Theme.primary
        case .warning: return Theme.warn
        case .neutral: return Theme.muted
        }
    }
}

struct ScatterItem: Identifiable {
    let id: Int
    let sleep: Double
    let delta: Double
}
