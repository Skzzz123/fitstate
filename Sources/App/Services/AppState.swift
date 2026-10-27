import Foundation
import WidgetKit

/// App 的单一数据源。
@MainActor
final class AppState: ObservableObject {

    static let shared = AppState()

    // MARK: - 状态

    @Published private(set) var metrics: [DailyMetrics] = []
    @Published private(set) var baseline = Baseline()
    @Published private(set) var breakdown: ScoreBreakdown?
    @Published private(set) var points: [TrendPoint] = []
    @Published private(set) var insights: [Insight] = []
    @Published private(set) var authorization: AuthorizationState = .notDetermined
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?

    @Published var errorMessage: String?

    @Published var settings: AppSettings = .default {
        didSet { settings.save() }
    }

    private let health = HealthKitService.shared

    // MARK: - 派生数据

    var today: DailyMetrics? { metrics.last }

    var todayMetrics: DailyMetrics? {
        guard let today else { return nil }
        let key = today.dayKey
        return metrics.first(where: { $0.dayKey == key })
    }

    var todayScore: Double? { breakdown?.score }

    var tier: ReadinessTier? { breakdown?.tier }

    var todayWorkouts: [WorkoutSummary] { todayMetrics?.workouts ?? [] }

    /// 趋势页用的点数（只保留设置窗口内的天数）
    var visiblePoints: [TrendPoint] {
        Array(points.suffix(settings.baselineWindowDays))
    }

    // MARK: - 生命周期

    func bootstrap() async {
        settings = settings.load()
        authorization = await health.authorizationState()
        await refresh()
    }

    func requestAuthorization() async {
        do {
            try await health.requestAuthorization()
            authorization = await health.authorizationState()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 重新读取健康数据、重算基线与分数、刷新小组件。
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let fetchDays = min(90, settings.baselineWindowDays + 30)
            let fetched = try await health.fetchDailyMetrics(days: fetchDays)
            metrics = fetched

            authorization = await health.authorizationState()

            guard let today = metrics.last else {
                breakdown = nil
                points = []
                insights = []
                publishSnapshot()
                return
            }

            // 每一都用「留一法」基线：算某天时，基线里不含这一天。
            // 今天也不例外，口径全程一致。
            let todaysBaseline = BaselineEngine.build(
                from: metrics,
                windowDays: settings.baselineWindowDays,
                excluding: today.dayKey
            )
            baseline = todaysBaseline
            breakdown = ScoringEngine.evaluate(today: today, baseline: todaysBaseline, settings: settings)

            var newPoints: [TrendPoint] = []
            for day in metrics {
                let dayBaseline = BaselineEngine.build(
                    from: metrics,
                    windowDays: settings.baselineWindowDays,
                    excluding: day.dayKey
                )
                let result = ScoringEngine.evaluate(today: day, baseline: dayBaseline, settings: settings)
                newPoints.append(
                    TrendPoint(
                        id: day.dayKey,
                        dayKey: day.dayKey,
                        date: day.date,
                        score: result.score,
                        hrvMS: day.hrvMS,
                        restingHR: day.restingHR,
                        sleepSeconds: day.hasSleepData ? day.totalSleep : nil,
                        deepSeconds: day.deepSleep > 0 ? day.deepSleep : nil,
                        hasWorkout: !day.workouts.isEmpty,
                        workoutNames: day.workouts.map { $0.displayName }
                    )
                )
            }
            points = newPoints

            insights = InsightEngine.insights(
                points: newPoints,
                baseline: todaysBaseline,
                windowDays: settings.baselineWindowDays
            )

            lastUpdated = Date()
            publishSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 把今日状态写进共享容器，并请求小组件刷新。
    private func publishSnapshot() {
        let snapshot = makeSnapshot()
        SnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func makeSnapshot() -> FitStateSnapshot {
        var metrics: [SnapshotMetric] = []
        for dimension in breakdown?.dimensions ?? [] {
            metrics.append(
                SnapshotMetric(
                    key: dimension.key.rawValue,
                    label: dimension.label,
                    score: dimension.score,
                    valueText: dimension.todayText,
                    baselineText: dimension.baselineText,
                    deltaText: dimension.deltaText,
                    isDrag: dimension.isDrag
                )
            )
        }
        return FitStateSnapshot(
            generatedAt: Date(),
            dayKey: breakdown?.dayKey ?? Fmt.dayKey(Date()),
            score: breakdown?.score,
            tier: breakdown?.tier?.label,
            headline: breakdown?.headline,
            advice: breakdown?.advice,
            metrics: metrics,
            baselineNote: breakdown?.baselineNote
        )
    }

    // MARK: - 导出

    /// 导出为 CSV，方便自己做进一步分析
    func exportCSV() -> String {
        var lines: [String] = []
        lines.append("日期,状态分,分档,HRV(ms),静息心率(bpm),睡眠时长(min),深睡(min),REM(min),睡眠效率,训练")
        for point in points {
            let metrics = self.metrics.first(where: { $0.dayKey == point.dayKey })
            let sleepMinutes = metrics.map { Int(($0.totalSleep / 60).rounded()) } ?? 0
            let deepMinutes = metrics.map { Int(($0.deepSleep / 60).rounded()) } ?? 0
            let remMinutes = metrics.map { Int(($0.remSleep / 60).rounded()) } ?? 0
            let efficiency = metrics?.sleepEfficiency.map { String(format: "%.3f", $0) } ?? ""
            let workouts = point.workoutNames.joined(separator: " / ")
            lines.append([
                point.dayKey,
                point.score.map { String(format: "%.1f", $0) } ?? "",
                point.score.map { ReadinessTier.from(score: $0).label } ?? "",
                metrics?.hrvMS.map { String(format: "%.1f", $0) } ?? "",
                metrics?.restingHR.map { String(format: "%.1f", $0) } ?? "",
                String(sleepMinutes),
                String(deepMinutes),
                String(remMinutes),
                efficiency,
                workouts
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}
