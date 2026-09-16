import Foundation
import CoreLocation
import Observation
import OSLog
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

    private static let log = Logger(subsystem: "name.dongharyu.RunCanvas", category: "run")

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
    /// 워치가 관리할 땐 워치의 HealthKit 거리(GPS+걸음 융합)가 진실이다 — 폰 GPS 체인은 터널·고가 밑에서
    /// 정확도가 나빠져 얼어붙고, 건강 앱에 남는 워치 기록과 폰 기록이 수백 m 어긋났다.
    /// nil 이면 폰 GPS 가 출처.
    private var watchDistanceMeters: Double?
    /// 출처(워치↔폰)가 바뀔 때 거리가 뒤로 점프하거나 두 배로 쌓이지 않게, 바뀐 시점의 거리를 이어 주는 기준점
    private var distanceBase: Double = 0

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

    var distanceMeters: Double { distanceBase + (watchDistanceMeters ?? location.totalDistance) }
    var route: [RoutePoint] { location.route }
    var currentLocation: CLLocation? { location.currentLocation }
    var locationAuthorization: CLAuthorizationStatus { location.authorization }

    func requestLocationPermission() { location.requestPermission() }

    func requestHealthAuthorization() async throws {
        try await health?.requestAuthorization()
    }

    /// 지금 달리는 구간의 경과. 벽시계가 뒤로 가도(자동 시간 보정·수동 변경) 음수가 화면·기록에 남지 않게 0 하한.
    private var liveSeconds: TimeInterval {
        segmentStart.map { max(0, now().timeIntervalSince($0)) } ?? 0
    }

    var elapsedSeconds: Int {
        _ = tick
        return Int((accumulated + liveSeconds).rounded(.down))
    }

    func start(sessionID: UUID = UUID(), healthManagedExternally: Bool = false) {
        // 세션은 앱 수명(RunCoordinator)이라 finish 뒤에도 같은 객체로 다음 러닝을 시작한다 —
        // .finished를 막으면 두 번째 러닝부터 시작이 안 되고, 지난 러닝의 시간·심박은 여기서 비워야 안 섞인다
        guard state == .idle || state == .finished else { return }
        accumulated = 0
        tick = 0
        heartRate = nil
        heartRateSamples = []
        self.sessionID = sessionID
        self.healthManagedExternally = healthManagedExternally
        watchDistanceMeters = nil
        distanceBase = 0
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

    /// running·paused가 아니면 nil — 종료 버튼 연타나 워치 end 중복으로 같은 러닝이 두 번 저장되지 않게
    @discardableResult
    func finish(ownerID: UUID, weightKg: Double, context: ModelContext) -> Run? {
        guard state == .running || state == .paused else { return nil }
        if state == .running {
            settleTime()
            location.stop()
        }
        ticker?.invalidate()
        if !RunSavePolicy.shouldSave(distanceMeters: distanceMeters) {
            health?.stopHeartRateStream()
            Self.discardRecoverable()
            state = .finished
            return nil
        }
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
        do {
            try context.save()
            Self.discardRecoverable()
        } catch {
            // 저장이 실패하면 체크포인트를 지우지 않고 최종 상태로 덮어 둔다 —
            // 다음 실행의 "이전 러닝이 중단됐어요" 알럿이 이 러닝을 되살릴 마지막 길이다
            Self.log.error("러닝 저장 실패: \(error.localizedDescription, privacy: .public)")
            saveCheckpoint()
        }
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
        state = .finished
        say(VoiceCue.finish(distanceMeters: run.distanceMeters, seconds: run.movingSeconds))
        return run
    }

    /// 달린 시간을 정산하고 구간을 닫는다. pause와 finish가 같이 쓴다 — finish가 pause를 부르면
    /// "일시정지" 안내가 먼저 나와버려서 분리했다.
    private func settleTime() {
        accumulated += liveSeconds
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
    static func save(_ recovered: RecoveredRun, ownerID: UUID, weightKg: Double, context: ModelContext) -> Run? {
        guard RunSavePolicy.shouldSave(distanceMeters: recovered.distanceMeters) else {
            discardRecoverable()
            return nil
        }
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
        do {
            try context.save()
            discardRecoverable()    // 성공했을 때만 — 실패하면 다음 실행에서 다시 물어본다
        } catch {
            log.error("중단 러닝 저장 실패: \(error.localizedDescription, privacy: .public)")
        }
        return run
    }

    private func saveCheckpoint() {
        guard state == .running || state == .paused, let startedAt else { return }
        let snapshot = RecoveredRun(
            sessionID: sessionID,
            startedAt: startedAt,
            accumulated: accumulated + liveSeconds,
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

    /// 건강 권한을 러닝 시작 뒤에 받았을 때 심박 스트림을 다시 건다.
    /// (start 시점엔 권한이 없어 스트림이 빈손으로 돌아온다 — 권한이 오면 그때 다시 걸어야 BPM이 들어온다)
    func restartHeartRateStream() {
        guard state == .running, !healthManagedExternally, let startedAt else { return }
        health?.startHeartRateStream(since: startedAt) { [weak self] bpm in
            self?.recordHeartRate(bpm)
        }
    }

    /// 화면(따라뛰기 등)이 한 문장 안내를 부탁할 때. 음성 안내가 꺼져 있으면 조용히 무시한다.
    func announce(_ text: String) { say(text) }

    func recordHeartRate(_ bpm: Double) {   // Phase 3에서 호출
        heartRate = bpm
        heartRateSamples.append(bpm)
    }

    /// 워치 스냅샷의 HealthKit 거리. 폰이 인계한 뒤 늦게 오는 값은 무시한다.
    /// 첫 값에서 기준점을 잡는다 — 워치가 폰보다 늦게 열렸으면 워치 거리엔 앞 구간이 빠져 있으니 폰이 센 거리를
    /// 지키고 증가분만 잇고, 워치가 먼저 시작해 폰이 늦게 합류했으면 워치 누적을 그대로 쓴다.
    /// 두 구간은 항상 지금 끝나는 포개진 구간이라 큰 쪽이 맞다 (그냥 갈아타면 거리가 뒤로 점프하고 기록이 준다).
    func recordWatchDistance(_ meters: Double) {
        guard healthManagedExternally else { return }
        if watchDistanceMeters == nil { distanceBase = max(0, distanceMeters - meters) }
        watchDistanceMeters = meters
    }

    /// 폰 단독으로 달리다 워치가 같은 세션으로 합류하면(시작 타임아웃 뒤 늦게 열림·손목에서 직접 시작)
    /// HealthKit 기록을 워치에 넘긴다. 예전엔 워치를 끝내 버려서 시작하자마자 멈추고 워치 기록이 사라졌다.
    /// 거리는 recordWatchDistance 의 첫 값 규칙대로 잇는다 — 워치 누적을 그냥 더하면 겹치는 구간이 두 번 쌓인다.
    func joinWatchWorkout(distanceMeters watchMeters: Double) {
        guard !healthManagedExternally, state == .running || state == .paused else { return }
        healthManagedExternally = true
        health?.stopHeartRateStream()   // 워치 스냅샷 심박과 이중으로 쌓이지 않게
        recordWatchDistance(watchMeters)
    }

    /// 워치 시작에 실패했거나 시작 타임아웃이 지났을 때 iPhone HealthKit 기록으로 전환한다.
    func takeOverHealthWorkout(since takeoverDate: Date = .now) {
        guard healthManagedExternally,
              state == .running || state == .paused else { return }
        healthManagedExternally = false
        distanceBase = distanceMeters - location.totalDistance   // 지금 거리에서 폰 GPS 로 이어서 센다
        watchDistanceMeters = nil
        // 왜: 러닝 시작 시각부터 다시 읽으면 워치 스냅샷으로 이미 담은 심박이 HealthKit에서
        // 다시 와 평균에 두 번 들어간다. 마지막 워치 응답 이후만 폰이 이어받는다.
        health?.startHeartRateStream(since: takeoverDate) { [weak self] bpm in
            self?.recordHeartRate(bpm)
        }
    }

    private func startTicker() {
        ticker?.invalidate()
        // 기본 런루프 모드 타이머는 화면을 스크롤하는 동안 안 돈다 — 시간 표시가 멈추고 음성 안내가 밀린다
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick += 1
            self.checkVoiceCue()
            if self.tick % 30 == 0 { self.saveCheckpoint() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }
}
