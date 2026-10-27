import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct FitStateEntry: TimelineEntry {
    let date: Date
    let snapshot: FitStateSnapshot
}

struct FitStateProvider: TimelineProvider {

    func placeholder(in context: Context) -> FitStateEntry {
        FitStateEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (FitStateEntry) -> Void) {
        completion(FitStateEntry(date: Date(), snapshot: SnapshotStore.read() ?? .preview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FitStateEntry>) -> Void) {
        let snapshot = SnapshotStore.read() ?? .empty
        let now = Date()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: [FitStateEntry(date: now, snapshot: snapshot)], policy: .after(next)))
    }
}

// MARK: - 交互式刷新（iOS 17+）

/// 点击后拉起主 App，主 App 会重新读取健康数据并回写快照。
struct RefreshStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "刷新状态"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

// MARK: - 视图

struct FitStateWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FitStateEntry

    private var score: Double? { entry.snapshot.score }
    private var tint: Color {
        guard let score else { return Color(red: 0.486, green: 0.478, blue: 0.447) }
        return WidgetPalette.color(for: score)
    }

    var body: some View {
        switch family {
        case .systemMedium:
            mediumLayout
        default:
            smallLayout
        }
    }

    // 小尺寸
    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                ring(size: 52, lineWidth: 6)
                Spacer(minLength: 0)
                refreshButton
            }

            Spacer(minLength: 0)

            Text(entry.snapshot.tier ?? "等待数据")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: 0.078, green: 0.090, blue: 0.118))
                .lineLimit(1)

            Text(shortAdvice)
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.486, green: 0.478, blue: 0.447))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(entry.snapshot.generatedAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color(red: 0.63, green: 0.62, blue: 0.58))
        }
    }

    // 中尺寸
    private var mediumLayout: some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                ring(size: 78, lineWidth: 8)
                Text(entry.snapshot.tier ?? "等待数据")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(red: 0.486, green: 0.478, blue: 0.447))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(headline)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.078, green: 0.090, blue: 0.118))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    refreshButton
                }

                ForEach(entry.snapshot.metrics.prefix(3)) { metric in
                    HStack(spacing: 6) {
                        Text(metric.label)
                            .font(.system(size: 10))
                            .foregroundStyle(Color(red: 0.486, green: 0.478, blue: 0.447))
                            .frame(width: 34, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(red: 0.945, green: 0.925, blue: 0.882))
                                Capsule()
                                    .fill(WidgetPalette.color(for: metric.score ?? 0))
                                    .frame(width: max(0, min(1, (metric.score ?? 0) / 100)) * geo.size.width)
                            }
                        }
                        .frame(height: 5)
                        Text(metric.score.map { String(format: "%.0f", $0) } ?? "--")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(red: 0.078, green: 0.090, blue: 0.118))
                            .frame(width: 20, alignment: .trailing)
                    }
                }

                Text(entry.snapshot.generatedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(red: 0.63, green: 0.62, blue: 0.58))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 组件

    private func ring(size: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Color(red: 0.945, green: 0.925, blue: 0.882), lineWidth: lineWidth)
            if let score {
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, score / 100)))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(score.map { String(format: "%.0f", $0) } ?? "--")
                .font(.system(size: size * 0.36, weight: .medium, design: .serif))
                .foregroundStyle(Color(red: 0.078, green: 0.090, blue: 0.118))
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var refreshButton: some View {
        if #available(iOS 17.0, *) {
            Button(intent: RefreshStatusIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.486, green: 0.478, blue: 0.447))
            }
            .buttonStyle(.plain)
        }
    }

    private var shortAdvice: String {
        guard let score else { return "打开 App 完成授权" }
        return WidgetPalette.advice(for: score)
    }

    private var headline: String {
        entry.snapshot.headline ?? "打开 App 完成授权"
    }
}

enum WidgetPalette {
    static func color(for score: Double) -> Color {
        switch score {
        case 85...: return Color(red: 0.184, green: 0.435, blue: 0.369)
        case 70..<85: return Color(red: 0.310, green: 0.565, blue: 0.467)
        case 55..<70: return Color(red: 0.788, green: 0.482, blue: 0.247)
        case 40..<55: return Color(red: 0.753, green: 0.439, blue: 0.290)
        default: return Color(red: 0.690, green: 0.388, blue: 0.404)
        }
    }

    static func advice(for score: Double) -> String {
        switch score {
        case 85...: return "可以上强度"
        case 70..<85: return "正常训练"
        case 55..<70: return "降强度控量"
        case 40..<55: return "只做轻量活动"
        default: return "今天休息"
        }
    }
}

// MARK: - Widget

struct FitStateWidget: Widget {
    let kind = "FitStateWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FitStateProvider()) { entry in
            FitStateWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(red: 0.984, green: 0.980, blue: 0.969)
                }
        }
        .configurationDisplayName("今天状态")
        .description("用睡眠和 HRV 判断今天该不该练")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct FitStateWidgetBundle: WidgetBundle {
    var body: some Widget {
        FitStateWidget()
    }
}
