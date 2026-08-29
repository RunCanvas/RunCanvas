import Foundation
import HealthKit

/// 워크아웃 상태·수치는 전부 메인 액터에서만 만진다 — 원격 명령(Task)과 1초 타이머가 같은 값을 건드려서
/// 클래스 전체를 @MainActor로 묶었다. HealthKit 델리게이트 콜백만 nonisolated로 받아 메인으로 넘긴다.
@MainActor
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

    /// 폰 스냅샷이 5초 넘게 안 오면 얼어붙은 값 대신 워치 자체 값을 보여준다
    private static let snapshotStaleAfter: TimeInterval = 5
    private var syncedAt: Date?

    private var phoneSyncIsFresh: Bool {
        guard isPhoneReachable, let syncedAt else { return false }
        return Date().timeIntervalSince(syncedAt) < Self.snapshotStaleAfter
    }

    var displayedDistanceMeters: Double {
        phoneSyncIsFresh ? (syncedDistanceMeters ?? distanceMeters) : distanceMeters
    }

    var displayedElapsedSeconds: Int {
        phoneSyncIsFresh ? (syncedElapsedSeconds ?? elapsedSeconds) : elapsedSeconds
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
            syncedAt = nil

            let startDate = Date()
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)

            state = .running
            startTimer()
            if sendToPhone {
                connectivity.sendCommand(.start, sessionID: sessionID)
            }
            sendSnapshot()
        } catch {
            errorMessage = error.localizedDescription
            connectivity.sendCommand(.unavailable, sessionID: sessionID)
            resetSession()
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
            state = .finished
            stopTimer()
            workoutSession = nil        // 중복 .end가 와도 위 guard에서 조용히 걸린다 (에러 알럿 방지)
            workoutBuilder = nil
            sendSnapshot()
        } catch {
            errorMessage = error.localizedDescription
            resetSession()
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
            MainActor.assumeIsolated {   // 메인 런루프 타이머라 이미 메인이다
                guard let self, let builder = self.workoutBuilder else { return }
                self.elapsedSeconds = Int(builder.elapsedTime(at: Date()))
                self.sendSnapshot()
            }
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
            guard state == .idle || state == .finished else {
                // 양쪽에서 거의 동시에 시작한 경우 — 폰을 마스터로 보고 세션 ID를 맞춘다.
                // (안 맞추면 이후 pause/resume/end가 전부 ID 불일치로 무시된다)
                self.sessionID = sessionID
                return
            }
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
        syncedAt = Date()
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.errorMessage = message
                self?.resetSession()
            }
        }
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let updates = collectedTypes.compactMap { type -> (HKQuantityType, HKStatistics)? in
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { return nil }
            return (quantityType, statistics)
        }

        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                updates.forEach { self.updateStatistics($0.1, for: $0.0) }
                self.sendSnapshot()   // 콜백당 1회 (예전엔 루프 안이라 3~5회 전송됐다)
            }
        }
    }
}

private enum WatchWorkoutError: LocalizedError {
    case healthDataUnavailable

    var errorDescription: String? {
        "이 Apple Watch에서는 건강 데이터를 사용할 수 없습니다."
    }
}
