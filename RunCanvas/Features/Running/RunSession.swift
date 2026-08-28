import Foundation
import CoreLocation
import Observation
import SwiftData

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
    private var healthManagedExternally = false

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

    var distanceMeters: Double { location.totalDistance }
    var route: [RoutePoint] { location.route }
    var currentLocation: CLLocation? { location.currentLocation }

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
        guard state == .running, let seg = segmentStart else { return }
        accumulated += now().timeIntervalSince(seg)
        segmentStart = nil
        location.stop()
        state = .paused
        ticker?.invalidate()
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
        if state == .running { pause() }
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
            Task { try? await health.saveWorkout(run) }
        }
        state = .finished
        say(VoiceCue.finish(distanceMeters: run.distanceMeters, seconds: run.movingSeconds))
        return run
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

    func recordHeartRate(_ bpm: Double) {   // Phase 3에서 호출
        heartRate = bpm
        heartRateSamples.append(bpm)
    }

    /// 워치 시작에 실패했을 때 iPhone HealthKit 기록으로 안전하게 전환한다.
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
            self?.tick += 1
            self?.checkVoiceCue()
        }
    }
}
