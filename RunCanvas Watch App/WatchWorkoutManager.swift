import Foundation
import HealthKit

final class WatchWorkoutManager: NSObject, ObservableObject {
    enum State {
        case idle
        case running
        case paused
        case finished
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var heartRate: Double?
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var activeEnergy: Double = 0
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var syncedDistanceMeters: Double?
    @Published private(set) var syncedElapsedSeconds: Int?
    @Published private(set) var isPhoneReachable = false
    @Published var errorMessage: String?

    var displayedDistanceMeters: Double {
        isPhoneReachable ? (syncedDistanceMeters ?? distanceMeters) : distanceMeters
    }

    var displayedElapsedSeconds: Int {
        isPhoneReachable ? (syncedElapsedSeconds ?? elapsedSeconds) : elapsedSeconds
    }

    private let healthStore = HKHealthStore()
    private let connectivity = WatchConnectivityService()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var timer: Timer?
    private(set) var sessionID = UUID()

    override init() {
        super.init()
        connectivity.onReachabilityChange = { [weak self] reachable in
            self?.isPhoneReachable = reachable
        }
        connectivity.onCommand = { [weak self] action, sessionID in
            self?.applyRemoteCommand(action, sessionID: sessionID)
        }
        connectivity.onSnapshot = { [weak self] snapshot in
            self?.applyPhoneSnapshot(snapshot)
        }
    }

    func start(sessionID: UUID = UUID(), sendToPhone: Bool = true) async {
        self.sessionID = sessionID
        do {
            try await requestAuthorization()

            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .running
            configuration.locationType = .outdoor

            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            session.delegate = self
            builder.delegate = self

            workoutSession = session
            workoutBuilder = builder
            heartRate = nil
            distanceMeters = 0
            activeEnergy = 0
            elapsedSeconds = 0
            syncedDistanceMeters = nil
            syncedElapsedSeconds = nil

            let startDate = Date()
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)

            await MainActor.run {
                state = .running
                startTimer()
                if sendToPhone {
                    connectivity.sendCommand(.start, sessionID: sessionID)
                }
                sendSnapshot()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                connectivity.sendCommand(.unavailable, sessionID: sessionID)
                resetSession()
            }
        }
    }

    func pause(sendToPhone: Bool = true) {
        guard state == .running else { return }
        workoutSession?.pause()
        state = .paused
        if sendToPhone { connectivity.sendCommand(.pause, sessionID: sessionID) }
        sendSnapshot()
    }

    func resume(sendToPhone: Bool = true) {
        guard state == .paused else { return }
        workoutSession?.resume()
        state = .running
        if sendToPhone { connectivity.sendCommand(.resume, sessionID: sessionID) }
        sendSnapshot()
    }

    func end(sendToPhone: Bool = true) async {
        guard let session = workoutSession, let builder = workoutBuilder else { return }

        if sendToPhone { connectivity.sendCommand(.end, sessionID: sessionID) }
        session.end()
        do {
            try await builder.endCollection(at: Date())
            _ = try await builder.finishWorkout()
            await MainActor.run {
                state = .finished
                stopTimer()
                sendSnapshot()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                resetSession()
            }
        }
    }

    private func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw WatchWorkoutError.healthDataUnavailable
        }

        let heartRate = HKQuantityType(.heartRate)
        let distance = HKQuantityType(.distanceWalkingRunning)
        let activeEnergy = HKQuantityType(.activeEnergyBurned)
        let workout = HKObjectType.workoutType()

        let typesToShare: Set<HKSampleType> = [workout, heartRate, distance, activeEnergy]
        let typesToRead: Set<HKObjectType> = [heartRate, distance, activeEnergy]
        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let builder = self.workoutBuilder else { return }
            self.elapsedSeconds = Int(builder.elapsedTime(at: Date()))
            self.sendSnapshot()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func resetSession() {
        workoutSession = nil
        workoutBuilder = nil
        stopTimer()
        state = .idle
    }

    private func updateStatistics(_ statistics: HKStatistics, for type: HKQuantityType) {
        switch type.identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue:
            let unit = HKUnit.count().unitDivided(by: .minute())
            heartRate = statistics.mostRecentQuantity()?.doubleValue(for: unit)
        case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
            distanceMeters = statistics.sumQuantity()?.doubleValue(for: .meter()) ?? distanceMeters
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
            activeEnergy = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? activeEnergy
        default:
            break
        }
        sendSnapshot()
    }

    private func sendSnapshot() {
        guard state == .running || state == .paused || state == .finished else { return }
        connectivity.sendSnapshot(
            sessionID: sessionID,
            state: stateString,
            elapsedSeconds: elapsedSeconds,
            distanceMeters: distanceMeters,
            heartRate: heartRate
        )
    }

    private var stateString: String {
        switch state {
        case .idle: "idle"
        case .running: "running"
        case .paused: "paused"
        case .finished: "finished"
        }
    }

    private func applyRemoteCommand(_ action: WorkoutSyncAction, sessionID: UUID) {
        switch action {
        case .start:
            guard state == .idle || state == .finished else { return }
            Task { await start(sessionID: sessionID, sendToPhone: false) }
        case .pause:
            guard sessionID == self.sessionID else { return }
            pause(sendToPhone: false)
        case .resume:
            guard sessionID == self.sessionID else { return }
            resume(sendToPhone: false)
        case .end:
            guard sessionID == self.sessionID else { return }
            Task { await end(sendToPhone: false) }
        case .unavailable:
            break
        }
    }

    private func applyPhoneSnapshot(_ snapshot: PhoneWorkoutSnapshot) {
        guard snapshot.sessionID == sessionID,
              state == .running || state == .paused else { return }
        syncedDistanceMeters = snapshot.distanceMeters
        syncedElapsedSeconds = snapshot.elapsedSeconds
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = error.localizedDescription
            self?.resetSession()
        }
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let updates = collectedTypes.compactMap { type -> (HKQuantityType, HKStatistics)? in
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { return nil }
            return (quantityType, statistics)
        }

        DispatchQueue.main.async { [weak self] in
            updates.forEach { self?.updateStatistics($0.1, for: $0.0) }
        }
    }
}

private enum WatchWorkoutError: LocalizedError {
    case healthDataUnavailable

    var errorDescription: String? {
        "이 Apple Watch에서는 건강 데이터를 사용할 수 없습니다."
    }
}
