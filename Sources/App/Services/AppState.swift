import Combine
import Foundation
import WidgetKit

/// 当前数据来自哪里。
enum DataSource: String {
    case none
    case healthKit
    case shortcut
    case csv

    var label: String {
        switch self {
        case .none: return "暂无数据"
        case .healthKit: return "「健康」App"
        case .shortcut: return "快捷指令"
        case .csv: return "CSV 导入"
        }
    }
}

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
    /// 备用数据源（Documents 里的 CSV）里有多少天数据
    @Published private(set) var importedDays = 0
    /// 「快捷指令 → App Intent」写进来的数据有多少天
    @Published private(set) var manualDays = 0
    /// 当前数据是不是靠 CSV 兜底撑着的
    @Published private(set) var usingImportedData = false
    /// 当前实际用的数据来源
    @Published private(set) var dataSource: DataSource = .none

    /// 最近一次由 App Intent 写进来的记录（用来核对解析对不对）
    var latestManualRecord: ManualDayRecord? {
        ManualHealthStore.loadRecords().last
    }

    @Published var errorMessage: String?

    /// 上一次刷新还没跑完时又来了一次刷新请求 → 跑完补一次
    private var needsRefresh = false

    @Published var settings: AppSettings = .default {
        didSet { settings.save() }
    }

    private let health = HealthKitService.shared
    private var cancellables = Set<AnyCancellable>()

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
        observeManualDataChanges()
        authorization = await currentAuthorizationState()
        await refresh()
    }

    func requestAuthorization() async {
        guard HealthKitAvailability.isEnabled else {
            errorMessage = HealthKitAvailability.reasonText
            return
        }
        do {
            try await health.requestAuthorization()
            authorization = await currentAuthorizationState()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 快捷指令写完数据后会广播一条通知，这里收到就重算一次。
    private func observeManualDataChanges() {
        NotificationCenter.default.publisher(for: .fitStateManualDataChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in await self?.refresh() }
            }
            .store(in: &cancellables)
    }

    /// 没有 HealthKit 能力时不要去碰 HealthKit —— 缺 entitlement 会被系统直接杀掉。
    private func currentAuthorizationState() async -> AuthorizationState {
        guard HealthKitAvailability.isEnabled else { return .notSupported }
        return await health.authorizationState()
    }

    /// 重新读取健康数据、重算基线与分数、刷新小组件。
    func refresh() async {
        // 已经在刷新中就记一笔「待刷新」，等这次跑完再补一次。
        // 不然「回到前台时正好有一次刷新在飞」的场景会把这次刷新直接丢掉，
        // 界面就一直停在旧数据上 —— 看起来就像「快捷指令写不进去」。
        if isLoading {
            needsRefresh = true
            return
        }
        isLoading = true
        defer {
            isLoading = false
            if needsRefresh {
                needsRefresh = false
                Task { await self.refresh() }
            }
        }

        do {
            let fetchDays = min(90, settings.baselineWindowDays + 30)

            // 备用数据源 A：快捷指令 → App Intent 写进来的 JSON。
            // 免费账号拿不到 HealthKit 能力时，这是主力数据源。
            let manual = ManualHealthStore.load()
            manualDays = manual.count

            // 备用数据源 B：Documents 目录里的 CSV。
            let imported = ImportedHealthStore.load()
            importedDays = imported.count

            var fetched: [DailyMetrics] = []
            var healthError: Error?
            if HealthKitAvailability.isEnabled {
                do {
                    fetched = try await health.fetchDailyMetrics(days: fetchDays)
                } catch {
                    healthError = error
                }
            }

            if let healthError {
                // 有兜底数据时不算出错，只是数据来自文件
                errorMessage = (manual.isEmpty && imported.isEmpty) ? healthError.localizedDescription : nil
            }

            // 合并优先级：HealthKit > 快捷指令 > CSV
            // 但必须**逐字段**合并，不能按天整条去重 ——
            // 快捷指令那天可能只有 HRV/心率（睡眠通道没时长），
            // 按整条去重会把 CSV 里同一天的睡眠整条丢掉，
            // 于是「今天睡眠 0 分钟」，睡眠那 35% 权重直接消失。
            let healthCount = fetched.count
            var merged = DataMerger.merge(sources: [fetched, manual, imported])

            usingImportedData = healthCount == 0 && manual.isEmpty && !imported.isEmpty
            if healthCount > 0 {
                dataSource = .healthKit
            } else if !manual.isEmpty {
                dataSource = .shortcut
            } else if !imported.isEmpty {
                dataSource = .csv
            } else {
                dataSource = .none
            }

            metrics = merged

            authorization = await currentAuthorizationState()

            guard let today = metrics.last else {
                breakdown = nil
                points = []
                insights = []
                publishSnapshot()
                return
            }

            // 每一天都用「留一法」基线：算某天时，基线只取「那一天之前」的 N 天。
            // 今天也不例外，口径全程一致（趋势图和今天页用的是同一把尺子）。
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
