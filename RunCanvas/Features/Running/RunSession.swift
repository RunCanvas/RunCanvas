import Foundation
import CoreLocation
import Observation
import SwiftData

/// 앱이 죽어도 잃지 않도록 30초마다 디스크에 떠 두는 진행 중 러닝
struct RecoveredRun: Codable {
    let sessionID: UUID
    let startedAt: Date
    let accumulated: TimeInterval
    let distanceMeters: Double
    let route: [RoutePoint]
}

/// 러닝 상태 머신. 시간은 타이머 틱이 아니라 날짜 차이 누적 — 백그라운드 정지·타이머 드리프트와 무관.
@Observable
final class RunSession {
    enum State { case idle, running, paused, finished }

    private(set) var state: State = .idle
    private(set) var sessionID = UUID()
    var heartRate: Double?                // Phase 3: HealthService가 갱신
    private(set) var heartRateSamples: [Double] = []

    private let location: LocationService
    private let health: HealthServicing?
    private let coach: VoiceCoach?
    private let now: () -> Date
    private var nextCueMeters: Double = .infinity   // 다음 음성 안내 지점
    private var startedAt: Date?
    private var segmentStart: Date?       // 현재 달리는 구간 시작
    private var accumulated: TimeInterval = 0
    private var ticker: Timer?
    private var tick = 0                  // 뷰 갱신용 (Observation이 변화를 감지하도록)
    private(set) var healthManagedExternally = false

    init(
        location: LocationService = LocationService(),
        health: HealthServicing? = nil,
        coach: VoiceCoach? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.location = location
        self.health = health
        self.coach = coach
        self.now = now
    }

    /// 세션이 사라져도 타이머·백그라운드 위치 갱신이 런루프에 남지 않도록
    deinit {
        ticker?.invalidate()
        location.stop()
    }

    var distanceMeters: Double { location.totalDistance }
    var route: [RoutePoint] { location.route }
    var currentLocation: CLLocation? { location.currentLocation }
    var locationAuthorization: CLAuthorizationStatus { location.authorization }

    func requestLocationPermission() { location.requestPermission() }

    func requestHealthAuthorization() async throws {
        try await health?.requestAuthorization()
    }

    var elapsedSeconds: Int {
        _ = tick
        let live = segmentStart.map { now().timeIntervalSince($0) } ?? 0
        return Int((accumulated + live).rounded(.down))
    }

    func start(sessionID: UUID = UUID(), healthManagedExternally: Bool = false) {
        guard state == .idle else { return }
        self.sessionID = sessionID
        self.healthManagedExternally = healthManagedExternally
        location.requestPermission()
        location.reset()
        location.start()
        startedAt = now()
        segmentStart = startedAt
        state = .running
        if let startedAt, !healthManagedExternally {
            health?.startHeartRateStream(since: startedAt) { [weak self] bpm in
                self?.recordHeartRate(bpm)
            }
        }
        nextCueMeters = coach?.intervalMeters ?? .infinity
        startTicker()
        say(VoiceCue.start)
    }

    func pause() {
        guard state == .running else { return }
        settleTime()
        location.stop()
        state = .paused
        ticker?.invalidate()
        saveCheckpoint()
        say(VoiceCue.pause)
    }

    func resume() {
        guard state == .paused else { return }
        segmentStart = now()
        location.start()
        state = .running
        startTicker()
        say(VoiceCue.resume)
    }

    @discardableResult
    func finish(ownerID: UUID, weightKg: Double, context: ModelContext) -> Run {
        if state == .running {
            settleTime()
            location.stop()
        }
        ticker?.invalidate()
        let run = Run(
            ownerID: ownerID,
            startedAt: startedAt ?? now(),
            endedAt: now(),
            distanceMeters: distanceMeters,
            movingSeconds: elapsedSeconds,
            calories: RunMath.calories(distanceMeters: distanceMeters, weightKg: weightKg),
            averageHeartRate: heartRateSamples.isEmpty ? nil : heartRateSamples.reduce(0, +) / Double(heartRateSamples.count),
            maxHeartRate: heartRateSamples.max(),
            route: route
        )
        context.insert(run)
        try? context.save()
        health?.stopHeartRateStream()
        if let health, !healthManagedExternally {
            // SwiftData 모델은 여기(메인)서만 읽고, 백그라운드로 넘어가는 건 값 스냅샷뿐
            let summary = WorkoutSummary(
                startedAt: run.startedAt,
                endedAt: run.endedAt,
                distanceMeters: run.distanceMeters,
                calories: run.calories
            )
            Task { try? await health.saveWorkout(summary) }
        }
        Self.discardRecoverable()
        state = .finished
        say(VoiceCue.finish(distanceMeters: run.distanceMeters, seconds: run.movingSeconds))
        return run
    }

    /// 달린 시간을 정산하고 구간을 닫는다. pause와 finish가 같이 쓴다 — finish가 pause를 부르면
    /// "일시정지" 안내가 먼저 나와버려서 분리했다.
    private func settleTime() {
        guard let seg = segmentStart else { return }
        accumulated += now().timeIntervalSince(seg)
        segmentStart = nil
    }

    // MARK: - 중단 복구 (앱이 죽어도 진행 중인 러닝을 잃지 않게)

    private static let checkpointURL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("run-in-progress.json")

    /// 중단된 러닝이 남아 있으면 돌려준다 (없으면 nil)
    static func recoverable() -> RecoveredRun? {
        guard let data = try? Data(contentsOf: checkpointURL) else { return nil }
        return try? JSONDecoder().decode(RecoveredRun.self, from: data)
    }

    static func discardRecoverable() {
        try? FileManager.default.removeItem(at: checkpointURL)
    }

    /// 중단된 러닝을 그대로 기록으로 저장한다 (이어달리기는 없음 — 저장 아니면 버리기)
    @discardableResult
    static func save(_ recovered: RecoveredRun, ownerID: UUID, weightKg: Double, context: ModelContext) -> Run {
        let run = Run(
            ownerID: ownerID,
            startedAt: recovered.startedAt,
            endedAt: recovered.startedAt.addingTimeInterval(recovered.accumulated),
            distanceMeters: recovered.distanceMeters,
            movingSeconds: Int(recovered.accumulated.rounded(.down)),
            calories: RunMath.calories(distanceMeters: recovered.distanceMeters, weightKg: weightKg),
            route: recovered.route
        )
        context.insert(run)
        try? context.save()
        discardRecoverable()
        return run
    }

    private func saveCheckpoint() {
        guard state == .running || state == .paused, let startedAt else { return }
        let live = segmentStart.map { now().timeIntervalSince($0) } ?? 0
        let snapshot = RecoveredRun(
            sessionID: sessionID,
            startedAt: startedAt,
            accumulated: accumulated + live,
            distanceMeters: distanceMeters,
            route: route
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: Self.checkpointURL, options: .atomic)
    }

    // MARK: - 음성 안내

    private func say(_ text: String) {
        guard let coach, coach.isEnabled else { return }
        coach.speak(text)
    }

    /// 설정 간격(기본 1km)을 넘을 때마다 거리·시간·페이스를 읽어준다. 매초 틱에서 호출.
    func checkVoiceCue() {
        guard state == .running, let coach, coach.isEnabled, distanceMeters >= nextCueMeters else { return }
        coach.speak(VoiceCue.progress(distanceMeters: nextCueMeters, seconds: elapsedSeconds))
        nextCueMeters += coach.intervalMeters
    }

    /// 화면(따라뛰기 등)이 한 문장 안내를 부탁할 때. 음성 안내가 꺼져 있으면 조용히 무시한다.
    func announce(_ text: String) { say(text) }

    func recordHeartRate(_ bpm: Double) {   // Phase 3에서 호출
        heartRate = bpm
        heartRateSamples.append(bpm)
    }

    /// 워치 시작에 실패했거나 러닝 도중 워치가 끊겼을 때 iPhone HealthKit 기록으로 전환한다.
    func takeOverHealthWorkout() {
        guard healthManagedExternally,
              state == .running || state == .paused,
              let startedAt else { return }
        healthManagedExternally = false
        health?.startHeartRateStream(since: startedAt) { [weak self] bpm in
            self?.recordHeartRate(bpm)
        }
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick += 1
            self.checkVoiceCue()
            if self.tick % 30 == 0 { self.saveCheckpoint() }
        }
    }
}
