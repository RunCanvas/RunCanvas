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

        let readTypes: Set<HKObjectType> = [heartRate]
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

        let deliver: ([HKSample]?) -> Void = { samples in
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
