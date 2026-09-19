import Foundation
import HealthKit

/// 건강 앱에 넘길 값만 담은 스냅샷. SwiftData 모델(Run)을 백그라운드에서 읽지 않으려고
/// 메인 액터에서 미리 떠서 전달한다.
struct WorkoutSummary {
    let startedAt: Date
    let endedAt: Date
    let distanceMeters: Double
    let calories: Double
}

protocol HealthServicing: AnyObject {
    func requestAuthorization() async throws
    func startHeartRateStream(since startDate: Date, onSample: @escaping (Double) -> Void)
    func stopHeartRateStream()
    func saveWorkout(_ summary: WorkoutSummary) async throws
}

/// HealthKit 권한, 심박 스트림, 러닝 워크아웃 저장을 담당한다.
final class HealthService: HealthServicing {
    enum HealthError: LocalizedError {
        case unavailable
        case workoutSaveFailed

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "이 기기에서는 건강 데이터를 쓸 수 없어요."
            case .workoutSaveFailed:
                return "러닝 워크아웃을 건강 앱에 저장하지 못했어요."
            }
        }
    }

    private let healthStore: HKHealthStore
    private let streamLock = NSLock()
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var streamStartDate: Date?
    private var streamID = UUID()
    private var queryID = UUID()
    private var deliveredSampleIDs: Set<UUID> = []

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthError.unavailable
        }

        let heartRate = HKQuantityType(.heartRate)
        let distance = HKQuantityType(.distanceWalkingRunning)
        let activeEnergy = HKQuantityType(.activeEnergyBurned)
        let workout = HKObjectType.workoutType()

        // 워크아웃·거리·칼로리·경로까지 읽는 이유: 폰 앱이 꺼진 채 워치로 뛴 러닝을 건강 앱에서 가져온다.
        let readTypes: Set<HKObjectType> = [heartRate, workout, distance, activeEnergy, HKSeriesType.workoutRoute()]
        let shareTypes: Set<HKSampleType> = [workout, distance, activeEnergy]
        try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    func startHeartRateStream(since startDate: Date, onSample: @escaping (Double) -> Void) {
        let oldQuery: HKAnchoredObjectQuery?
        let activeStreamID: UUID
        let activeQueryID = UUID()
        streamLock.lock()
        oldQuery = heartRateQuery
        heartRateQuery = nil
        queryID = activeQueryID
        if streamStartDate != startDate {
            // 왜: 같은 러닝의 재시작은 중복을 막아야 하지만 다음 러닝의 샘플 UUID까지 막으면 안 된다.
            streamStartDate = startDate
            streamID = UUID()
            deliveredSampleIDs.removeAll(keepingCapacity: true)
        }
        activeStreamID = streamID
        streamLock.unlock()
        if let oldQuery { healthStore.stop(oldQuery) }

        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: nil,
            options: .strictStartDate
        )
        let unit = HKUnit.count().unitDivided(by: .minute())

        // [weak self]: deliver 를 쥔 query 를 self.heartRateQuery 에 저장하므로 순환이 생긴다.
        // 러닝이 정상 종료되지 않으면 쿼리가 계속 살아 배터리를 쓴다.
        let deliver: ([HKSample]?) -> Void = { [weak self] samples in
            guard let self else { return }
            let quantitySamples = (samples as? [HKQuantitySample])?.sorted { $0.startDate < $1.startDate } ?? []
            self.streamLock.lock()
            guard self.queryID == activeQueryID else {
                self.streamLock.unlock()
                return
            }
            let freshSamples = quantitySamples.filter { self.deliveredSampleIDs.insert($0.uuid).inserted }
            self.streamLock.unlock()
            let heartRates = freshSamples.map { $0.quantity.doubleValue(for: unit) }

            guard !heartRates.isEmpty else { return }
            DispatchQueue.main.async {
                self.streamLock.lock()
                let isCurrentRun = self.streamID == activeStreamID
                self.streamLock.unlock()
                guard isCurrentRun else { return }
                heartRates.forEach(onSample)
            }
        }

        let query = HKAnchoredObjectQuery(
            type: type,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { _, samples, _, _, _ in
            deliver(samples)
        }

        query.updateHandler = { _, samples, _, _, _ in
            deliver(samples)
        }

        streamLock.lock()
        let isCurrent = queryID == activeQueryID
        if isCurrent { heartRateQuery = query }
        streamLock.unlock()
        if isCurrent { healthStore.execute(query) }   // 외부 프레임워크 호출은 락 밖에서
    }

    func stopHeartRateStream() {
        streamLock.lock()
        let query = heartRateQuery
        heartRateQuery = nil
        streamStartDate = nil
        streamID = UUID()
        queryID = UUID()
        deliveredSampleIDs.removeAll(keepingCapacity: true)
        streamLock.unlock()
        if let query { healthStore.stop(query) }
    }

    func saveWorkout(_ summary: WorkoutSummary) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthError.unavailable
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor

        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: .local()
        )

        try await builder.beginCollection(at: summary.startedAt)

        var samples: [HKSample] = []
        if summary.distanceMeters > 0 {
            samples.append(
                HKQuantitySample(
                    type: HKQuantityType(.distanceWalkingRunning),
                    quantity: HKQuantity(unit: .meter(), doubleValue: summary.distanceMeters),
                    start: summary.startedAt,
                    end: summary.endedAt
                )
            )
        }
        if summary.calories > 0 {
            samples.append(
                HKQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: summary.calories),
                    start: summary.startedAt,
                    end: summary.endedAt
                )
            )
        }

        if !samples.isEmpty {
            try await add(samples, to: builder)
        }
        try await builder.endCollection(at: summary.endedAt)
        _ = try await builder.finishWorkout()
    }

    private func add(_ samples: [HKSample], to builder: HKWorkoutBuilder) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.add(samples) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthError.workoutSaveFailed)
                }
            }
        }
    }
}

// MARK: - 건강 앱에서 가져오기

extension HealthService {
    /// 우리 앱(폰·워치)이 건강 앱에 저장한 러닝 워크아웃. 다른 앱 기록은 가져오지 않는다(사용자 결정).
    /// 워치 앱은 폰과 다른 번들 ID(`...watchkitapp`)라 접두사로 함께 잡는다.
    func importableWorkouts(since: Date,
                            needsRoute: @escaping (ImportedWorkout) -> Bool) async throws -> [ImportedWorkout] {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthError.unavailable }
        let ours = (Bundle.main.bundleIdentifier ?? "").replacingOccurrences(of: ".watchkitapp", with: "")

        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .running),
            HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate)
        ])
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples as? [HKWorkout] ?? []) }
            }
            healthStore.execute(query)
        }

        var result: [ImportedWorkout] = []
        for workout in workouts
        where !ours.isEmpty && workout.sourceRevision.source.bundleIdentifier.hasPrefix(ours) {
            let heartRates = workout.statistics(for: HKQuantityType(.heartRate))
            let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
            // 경로 없이 먼저 만들어 호출자에게 물어본다 — 필요 없으면 무거운 경로 조회를 건너뛴다
            let summary = ImportedWorkout(
                id: workout.uuid,
                startedAt: workout.startDate,
                endedAt: workout.endDate,
                distanceMeters: workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                    .sumQuantity()?.doubleValue(for: .meter()) ?? 0,
                calories: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                    .sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0,
                averageHeartRate: heartRates?.averageQuantity()?.doubleValue(for: beatsPerMinute),
                maxHeartRate: heartRates?.maximumQuantity()?.doubleValue(for: beatsPerMinute),
                route: []
            )
            guard needsRoute(summary) else { result.append(summary); continue }
            result.append(ImportedWorkout(
                id: summary.id, startedAt: summary.startedAt, endedAt: summary.endedAt,
                distanceMeters: summary.distanceMeters, calories: summary.calories,
                averageHeartRate: summary.averageHeartRate, maxHeartRate: summary.maxHeartRate,
                route: (try? await route(of: workout)) ?? []
            ))
        }
        return result
    }

    /// 워치가 붙여 둔 경로. 없으면 빈 배열 — 지도 없는 기록으로 남는다(예전 워치 러닝은 경로가 없다).
    private func route(of workout: HKWorkout) async throws -> [RoutePoint] {
        let samples: [HKWorkoutRoute] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: HKQuery.predicateForObjects(from: workout),
                limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples as? [HKWorkoutRoute] ?? []) }
            }
            healthStore.execute(query)
        }
        guard let series = samples.first else { return [] }

        return try await withCheckedThrowingContinuation { continuation in
            var points: [RoutePoint] = []
            // 왜: continuation 을 두 번 재개하면 크래시다. done 이후에도 핸들러가 불릴 수 있어 한 번만 통과시킨다.
            var didResume = false
            let query = HKWorkoutRouteQuery(route: series) { query, locations, done, error in
                guard !didResume else { return }
                if let error {
                    didResume = true
                    self.healthStore.stop(query)
                    continuation.resume(throwing: error)
                    return
                }
                points += (locations ?? []).map {
                    RoutePoint(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude,
                               timestamp: $0.timestamp)
                }
                if done {
                    didResume = true
                    self.healthStore.stop(query)
                    continuation.resume(returning: points)
                }
            }
            healthStore.execute(query)
        }
    }
}
