import Foundation
import CoreLocation
import HealthKit
import WatchKit

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
    @Published private(set) var isPhoneReachable = false
    /// start()가 권한·beginCollection을 기다리는 동안 true — 뷰에서 시작 버튼을 잠그는 데 쓴다
    @Published private(set) var isStarting = false
    @Published var errorMessage: String?

    /// 폰 스냅샷이 5초 넘게 안 오면 얼어붙은 값 대신 워치 자체 값을 보여준다
    private static let snapshotStaleAfter: TimeInterval = 5
    private var syncedAt: Date?
    /// 시작 중(await)에 온 원격 명령. 세션이 아직 없어 그냥 버려지므로 기억해 뒀다가 start() 끝에서 처리한다
    /// (폰에서 시작하자마자 일시정지하면 워치만 계속 달리던 문제)
    private var pendingCommand: WorkoutSyncAction?

    /// 폰이 이 세션을 실제로 기록 중인지. `isPhoneReachable`(닿는다)과 다르다 —
    /// 폰이 위치 권한 등으로 시작을 거절하면 닿아도 스냅샷이 아예 안 온다.
    var isPhoneRecording: Bool { phoneSyncIsFresh }

    private var phoneSyncIsFresh: Bool {
        guard isPhoneReachable, let syncedAt else { return false }
        return Date().timeIntervalSince(syncedAt) < Self.snapshotStaleAfter
    }

    /// 거리만 폰 GPS 값을 우선한다 — 워치 단독 거리는 추정치라 덜 정확하다
    var displayedDistanceMeters: Double {
        phoneSyncIsFresh ? (syncedDistanceMeters ?? distanceMeters) : distanceMeters
    }

    /// 시간은 워치 builder.elapsedTime이 진실이다. 폰 값을 우선하면 워치가 먼저 시작했을 때 폰이 늦게 합류하는 순간
    /// 시간이 뒤로 점프했다가 스냅샷이 끊기면 다시 튀어오른다 (pause/resume은 명령으로 동기화되니 폰 값이 필요 없다)
    var displayedElapsedSeconds: Int { elapsedSeconds }

    /// 폰이 이만큼 기록 신호를 안 보내면 워치가 직접 GPS 를 켠다.
    /// 워치 GPS 는 배터리를 많이 먹어서, 폰이 기록 중이면(더 정확하다) 켜지 않는다.
    private static let ownRouteAfter: TimeInterval = 20

    private let healthStore = HKHealthStore()
    private let locationManager = CLLocationManager()
    private var routeBuilder: HKWorkoutRouteBuilder?
    /// 이번 러닝에서 워치가 경로를 모으기 시작했는지. 한 번 켜면 끝까지 유지한다 —
    /// 폰이 중간에 돌아왔다고 껐다 켜면 경로가 조각난다.
    private(set) var isRecordingOwnRoute = false
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
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .fitness
    }

    func start(sessionID: UUID = UUID(), sendToPhone: Bool = true) async {
        // 왜: 권한·beginCollection을 기다리는 동안 두 번째 start()(손목 두 번 탭, 폰 .start 동시 도착)가
        // 새 HKWorkoutSession을 만들면 HealthKit이 먼저 것을 실패시키고, 그 콜백이 두 번째 세션 참조까지 지워
        // UI는 idle인데 워크아웃은 계속 도는 상태가 된다
        guard !isStarting, state == .idle || state == .finished else { return }
        isStarting = true
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
            syncedAt = nil
            routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
            isRecordingOwnRoute = false
            // 권한은 미리 물어 둔다 — 폰이 끊긴 걸 알아챈 순간(러닝 중)에 시트를 띄우면 이미 늦다
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            }

            let startDate = Date()
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)

            state = .running
            WKInterfaceDevice.current().play(.start)   // 화면을 안 보는 손목에 탭이 먹었음을 알린다
            startTimer()
            if sendToPhone {
                connectivity.sendCommand(.start, sessionID: self.sessionID)
            }
            sendSnapshot()
        } catch {
            errorMessage = error.localizedDescription
            connectivity.sendCommand(.unavailable, sessionID: sessionID)
            resetSession()
        }
        isStarting = false   // defer로 두면 아래 end()가 다시 대기 명령으로 빠져 영영 안 끝난다
        let queued = pendingCommand
        pendingCommand = nil
        switch queued {
        case .end: await end(sendToPhone: false)   // 시작이 실패했으면 세션이 없어 guard에서 조용히 빠진다
        case .discard: await end(sendToPhone: false, discarding: true)
        case .pause: pause(sendToPhone: false)
        default: break
        }
    }

    func pause(sendToPhone: Bool = true) {
        if isStarting { pendingCommand = .pause; return }
        guard state == .running else { return }
        workoutSession?.pause()
        state = .paused
        WKInterfaceDevice.current().play(.click)
        if sendToPhone { connectivity.sendCommand(.pause, sessionID: sessionID) }
        sendSnapshot()
    }

    func resume(sendToPhone: Bool = true) {
        guard state == .paused else { return }
        workoutSession?.resume()
        state = .running
        WKInterfaceDevice.current().play(.click)
        if sendToPhone { connectivity.sendCommand(.resume, sessionID: sessionID) }
        sendSnapshot()
    }

    /// `discarding` 이면 건강 앱에 저장하지 않고 버린다 — 폰이 기록을 인계한 경우.
    func end(sendToPhone: Bool = true, discarding: Bool = false) async {
        if isStarting {
            pendingCommand = discarding ? .discard : .end
            return
        }
        guard let session = workoutSession, let builder = workoutBuilder else { return }
        // 왜: endCollection·finishWorkout을 기다리는 동안 두 번째 end()(손목 두 번 탭, 폰 .end 동시 도착)가
        // 위 guard를 통과해 endCollection을 두 번 부르면 throw→에러 알럿+idle로 튄다. await 전에 비워서 막는다
        workoutSession = nil
        workoutBuilder = nil
        stopTimer()   // 종료 탭 뒤에도 시간이 올라가면 안 먹은 줄 알고 다시 누른다
        WKInterfaceDevice.current().play(.stop)

        if sendToPhone { connectivity.sendCommand(.end, sessionID: sessionID) }
        session.end()
        guard !discarding else {
            // 폰이 이어서 기록 중이다. 여기서 저장하면 건강 앱에 몇 초~몇십 초짜리 조각이 하나 더 남는다.
            builder.discardWorkout()
            stopOwnRoute()
            routeBuilder = nil
            stopTimer()
            state = .idle
            return
        }
        let collectedRoute = isRecordingOwnRoute
        stopOwnRoute()
        do {
            try await builder.endCollection(at: Date())
            let workout = try await builder.finishWorkout()
            // 왜: 경로는 워크아웃이 저장된 뒤에야 붙일 수 있다(HKWorkout 이 있어야 한다).
            // 실패해도 러닝 자체는 이미 저장됐으므로 지도만 없는 기록으로 남긴다.
            if collectedRoute, let workout, let routeBuilder {
                do { try await routeBuilder.finishRoute(with: workout, metadata: nil) }
                catch { errorMessage = "경로를 저장하지 못했어요. 러닝 기록은 건강 앱에 저장됐어요." }
            }
            routeBuilder = nil
            state = .finished
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

        // 왜: 거부해도 requestAuthorization은 throw하지 않고 뒤의 beginCollection이 시스템 문구로만 실패해
        // 사용자가 어디서 켜야 하는지 모른 채 막힌다. 워크아웃 쓰기 권한이 없으면 여기서 안내문으로 끊는다
        guard healthStore.authorizationStatus(for: workout) != .sharingDenied else {
            throw WatchWorkoutError.sharingDenied
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {   // 메인 런루프 타이머라 이미 메인이다
                guard let self, let builder = self.workoutBuilder else { return }
                self.elapsedSeconds = Int(builder.elapsedTime(at: Date()))
                self.startOwnRouteIfPhoneIsNotRecording()
                self.sendSnapshot()
            }
        }
    }

    /// 폰이 기록 중이면 폰 GPS 가 더 정확하고 워치 배터리도 아낀다. 폰 스냅샷이 20초 넘게
    /// 없으면(폰을 두고 나왔거나, 폰 앱이 시작을 거절했거나) 워치가 직접 경로를 모은다.
    private func startOwnRouteIfPhoneIsNotRecording() {
        guard !isRecordingOwnRoute, state == .running,
              Double(elapsedSeconds) > Self.ownRouteAfter, !phoneSyncIsFresh else { return }
        guard [.authorizedWhenInUse, .authorizedAlways].contains(locationManager.authorizationStatus) else { return }
        isRecordingOwnRoute = true
        locationManager.allowsBackgroundLocationUpdates = true   // 손목을 내려도 계속 모은다
        locationManager.startUpdatingLocation()
    }

    private func stopOwnRoute() {
        guard isRecordingOwnRoute else { return }
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        isRecordingOwnRoute = false
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func resetSession() {
        // 왜: beginCollection 실패로 여기 오면 startActivity된 세션이 HealthKit에 살아 있어
        // 다음 start()가 errorAnotherWorkoutSessionStarted로 깨진다. 이미 끝난 세션이면 end()는 no-op
        workoutSession?.end()
        workoutSession = nil
        workoutBuilder = nil
        stopOwnRoute()
        routeBuilder = nil
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
            guard state == .idle || state == .finished, !isStarting else {
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
        case .discard:
            guard sessionID == self.sessionID else { return }
            Task { await end(sendToPhone: false, discarding: true) }
        case .unavailable:
            break
        }
    }

    private func applyPhoneSnapshot(_ snapshot: PhoneWorkoutSnapshot) {
        guard snapshot.sessionID == sessionID,
              state == .running || state == .paused else { return }
        syncedDistanceMeters = snapshot.distanceMeters
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
                // 왜: 버려진 옛 세션이 errorAnotherWorkoutSessionStarted로 실패한 콜백이
                // 방금 만든 현재 세션의 상태·타이머를 지우면 안 된다 (HKWorkoutSession은 Sendable)
                guard let self, self.workoutSession === workoutSession else { return }
                self.errorMessage = message
                // 안 알리면 폰은 스냅샷이 30초 끊길 때까지 워치가 기록 중인 줄 안다
                self.connectivity.sendCommand(.unavailable, sessionID: self.sessionID)
                self.resetSession()
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
    case sharingDenied

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            "이 Apple Watch에서는 건강 데이터를 사용할 수 없습니다."
        case .sharingDenied:
            "건강 데이터 권한이 꺼져 있어요. iPhone 건강 앱의 공유 > 앱 및 서비스에서 RunCanvas를 허용해 주세요."
        }
    }
}

extension WatchWorkoutManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // 왜: 워크아웃 경로에 실내·초기 흔들림이 섞이면 지도가 튄다. 수평 정확도 50m 안쪽만 담는다.
        let usable = locations.filter { $0.horizontalAccuracy > 0 && $0.horizontalAccuracy <= 50 }
        guard !usable.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self, self.isRecordingOwnRoute, let routeBuilder = self.routeBuilder else { return }
            try? await routeBuilder.insertRouteData(usable)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 일시적 실패는 다음 업데이트에서 회복된다 — 러닝을 멈출 이유는 아니다
    }
}
