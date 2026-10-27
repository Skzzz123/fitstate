import Foundation
import HealthKit

enum HealthDataError: LocalizedError {
    case unavailable
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "此设备不支持「健康」数据。"
        case .queryFailed(let message):
            return "读取健康数据失败：\(message)"
        }
    }
}

enum AuthorizationState: Equatable {
    case notDetermined
    case shouldRequest
    case unknown
    case denied

    var label: String {
        switch self {
        case .notDetermined: return "尚未授权"
        case .shouldRequest: return "需要授权"
        case .unknown: return "已授权"
        case .denied: return "权限不足"
        }
    }
}

/// HealthKit 只读数据层。
///
/// - 只申请 read 权限，`toShare` 恒为空 —— 这个 App 永远不会往「健康」里写东西。
/// - 一次拉取覆盖整段窗口，再按天分桶，避免逐日查询。
actor HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()
    private let cal = Calendar.current

    private var sleepType: HKCategoryType { HKObjectType.categoryType(forIdentifier: .sleepAnalysis)! }
    private var hrvType: HKQuantityType { HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)! }
    private var rhrType: HKQuantityType { HKObjectType.quantityType(forIdentifier: .restingHeartRate)! }

    private var hrUnit: HKUnit { HKUnit.secondUnit(with: .milli) }
    private var rateUnit: HKUnit { HKUnit.count().unitDivided(by: .minute()) }
    private var kcalUnit: HKUnit { HKUnit.kilocalorie() }

    private var readTypes: Set<HKObjectType> {
        [sleepType, hrvType, rhrType, HKObjectType.workoutType()]
    }

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - 授权

    func authorizationState() async -> AuthorizationState {
        guard HKHealthStore.isHealthDataAvailable() else { return .denied }
        return await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, _ in
                switch status {
                case .shouldRequest: continuation.resume(returning: .shouldRequest)
                case .unnecessary: continuation.resume(returning: .unknown)
                case .unknown: continuation.resume(returning: .notDetermined)
                @unknown default: continuation.resume(returning: .notDetermined)
                }
            }
        }
    }

    /// 发起授权请求。Apple 的健康数据权限弹窗由系统展示，用户可以选择逐项允许或拒绝。
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthDataError.unavailable }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: - 查询

    /// 拉取最近 `days` 天的日度指标（升序返回）。
    func fetchDailyMetrics(days: Int) async throws -> [DailyMetrics] {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthDataError.unavailable }

        let today = cal.startOfDay(for: Date())
        let firstDay = cal.date(byAdding: .day, value: -(max(0, days) - 1), to: today) ?? today
        let endExclusive = cal.date(byAdding: .day, value: 1, to: today) ?? today

        // 睡眠需要多往前取 8 小时，命中「前一天晚上入睡」的样本
        let sleepStart = cal.date(byAdding: .hour, value: -8, to: firstDay) ?? firstDay

        async let sleepTask = fetchSleepSamples(from: sleepStart, to: endExclusive)
        async let hrvTask = fetchQuantitySamples(hrvType, from: sleepStart, to: endExclusive)
        async let rhrTask = fetchQuantitySamples(rhrType, from: firstDay, to: endExclusive)
        async let workoutTask = fetchWorkouts(from: firstDay, to: endExclusive)

        let sleepSamples: [HKCategorySample]
        let hrvSamples: [HKQuantitySample]
        let rhrSamples: [HKQuantitySample]
        let workouts: [HKWorkout]

        do {
            sleepSamples = try await sleepTask
            hrvSamples = try await hrvTask
            rhrSamples = try await rhrTask
            workouts = try await workoutTask
        } catch {
            throw HealthDataError.queryFailed(error.localizedDescription)
        }

        var result: [DailyMetrics] = []

        var cursor = firstDay
        while cursor < endExclusive {
            let dayStart = cursor
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayEndFallback(dayStart)

            var metrics = DailyMetrics(dayKey: Fmt.dayKey(dayStart, calendar: cal), date: dayStart)

            // —— 睡眠：以「醒来的那天」归属，窗口 = 前一天 16:00 → 当天 20:00
            let (nightStart, nightEnd) = nightWindow(dayStart: dayStart)
            for sample in sleepSamples where sample.startDate >= nightStart && sample.startDate < nightEnd {
                let duration = sample.endDate.timeIntervalSince(sample.startDate)
                guard duration > 0 else { continue }
                let value = sample.value
                if value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue {
                    metrics.deepSleep += duration
                    metrics.totalSleep += duration
                } else if value == HKCategoryValueSleepAnalysis.asleepREM.rawValue {
                    metrics.remSleep += duration
                    metrics.totalSleep += duration
                } else if value == HKCategoryValueSleepAnalysis.asleepCore.rawValue {
                    metrics.coreSleep += duration
                    metrics.totalSleep += duration
                } else if value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue {
                    metrics.unspecifiedSleep += duration
                    metrics.totalSleep += duration
                } else if value == HKCategoryValueSleepAnalysis.awake.rawValue {
                    metrics.awakeInBed += duration
                } else if value == HKCategoryValueSleepAnalysis.inBed.rawValue {
                    metrics.inBed += duration
                }
            }

            // —— HRV：优先取夜间窗口的中位数（更贴近「昨晚的恢复水平」）
            let nightHRV = hrvSamples
                .filter { $0.startDate >= nightStart && $0.startDate < nightEnd }
                .map { $0.quantity.doubleValue(for: hrUnit) }
            let dayHRV = hrvSamples
                .filter { $0.startDate >= dayStart && $0.startDate < dayEnd }
                .map { $0.quantity.doubleValue(for: hrUnit) }
            metrics.hrvMS = Stats.median(nightHRV) ?? Stats.median(dayHRV)

            // —— 静息心率：当日平均值
            let dayRHR = rhrSamples
                .filter { $0.startDate >= dayStart && $0.startDate < dayEnd }
                .map { $0.quantity.doubleValue(for: rateUnit) }
            metrics.restingHR = Stats.average(dayRHR)

            // —— 训练记录（只读）
            for workout in workouts where workout.startDate >= dayStart && workout.startDate < dayEnd {
                let energy = workout.totalEnergyBurned?.doubleValue(for: kcalUnit)
                metrics.workouts.append(
                    WorkoutSummary(
                        activity: String(describing: workout.workoutActivityType),
                        start: workout.startDate,
                        duration: workout.duration,
                        energyKcal: energy
                    )
                )
            }

            result.append(metrics)
            cursor = dayEnd
        }

        return result
    }

    // MARK: - 私有查询

    private func dayEndFallback(_ dayStart: Date) -> Date {
        cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
    }

    /// 睡眠归属窗口：前一天 16:00 → 当天 20:00。
    private func nightWindow(dayStart: Date) -> (Date, Date) {
        let start = cal.date(byAdding: .hour, value: -8, to: dayStart) ?? dayStart.addingTimeInterval(-8 * 3600)
        let end = cal.date(byAdding: .hour, value: 20, to: dayStart) ?? dayStart.addingTimeInterval(20 * 3600)
        return (start, end)
    }

    private func fetchSleepSamples(from start: Date, to end: Date) async throws -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate, .strictEndDate]
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\HKSample.startDate, order: .forward)]
        )
        let samples = try await descriptor.result(for: store)
        return samples.compactMap { $0 as? HKCategorySample }
    }

    private func fetchQuantitySamples(_ type: HKQuantityType, from start: Date, to end: Date) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate, .strictEndDate]
        )
        let descriptor = HKQuantityQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.startDate, order: .forward)],
            quantityType: type
        )
        let samples = try await descriptor.result(for: store)
        return samples
    }

    private func fetchWorkouts(from start: Date, to end: Date) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate, .strictEndDate]
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\HKWorkout.startDate, order: .forward)]
        )
        let samples = try await descriptor.result(for: store)
        return samples.compactMap { $0 as? HKWorkout }
    }
}
