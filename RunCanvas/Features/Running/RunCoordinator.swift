import Foundation
import CoreLocation
import Observation
import SwiftData

/// 러닝 세션과 워치 연동을 앱 수명으로 들고 있는 코디네이터.
/// 예전엔 RunView.onAppear에서 onCommand/onSnapshot을 등록하고 onDisappear에서 nil로 지워서,
/// 탭만 옮겨도 워치의 심박·종료 명령이 버려지고 워치에서 시작한 러닝이 폰에 안 남았다.
@Observable
final class RunCoordinator {
    let session: RunSession

    /// 워치 → iPhone 기록 전환을 RunView가 알려주기 위한 1회성 문구
    var takeoverMessage: String?
    /// 종료된 러닝 — RunView가 떠 있으면 결과 화면을 띄운다 (없어도 저장은 이미 끝났다)
    var finishedRun: Run?
    var showsWatchRun = false
    var watchStartError: String?
    var showsDiscardedRun = false

    /// 세션이 만료돼 auth.userID가 사라져도 기록을 잃지 않도록 마지막 계정을 들고 있는다.
    /// nil 은 무시한다 — RootTabView 가 auth.userID 를 그대로 흘려보내므로, 러닝 중 토큰 갱신이
    /// 실패해 잠깐 nil 이 되면 이 값이 지워지고 finish() 가 저장하지 못한다(워치 종료 경로는
    /// 반환값을 버려서 아무 표시도 안 난다). 남아 있어도 해롭지 않다 — start() 가 세션을 따로
    /// 확인하고, 로그아웃하면 AppRouter 가 로그인 화면으로 보낸다.
    var ownerID: UUID? {
        get { UserDefaults.standard.string(forKey: Self.ownerKey).flatMap(UUID.init(uuidString:)) }
        set { if let newValue { UserDefaults.standard.set(newValue.uuidString, forKey: Self.ownerKey) } }
    }

    private static let ownerKey = "lastOwnerID"
    /// 워치가 .start를 받고도 이 시간 안에 스냅샷을 안 보내면 워크아웃을 못 연 걸로 본다.
    /// transferUserInfo 배달 + HealthKit 권한 시트까지 15초는 모자라서 헛인계가 잦았다
    private static let watchStartTimeout: TimeInterval = 30

    private let watch: WatchConnectivityService
    private let context: ModelContext
    private var watchStartedAt: Date?
    private var lastWatchSnapshotAt: Date?
    private var syncTask: Task<Void, Never>?

    var weightKg: Double {
        let v = UserDefaults.standard.double(forKey: "userWeight")
        return v > 0 ? v : 60
    }

    init(watch: WatchConnectivityService, context: ModelContext, session: RunSession) {
        self.watch = watch
        self.context = context
        self.session = session
        watch.onCommand = { [weak self] action, remoteSessionID in
            self?.handle(action, remoteSessionID: remoteSessionID)
        }
        watch.onSnapshot = { [weak self] snapshot in
            self?.apply(snapshot)
        }
        watch.onFinishedWorkout = { [weak self] finished in
            self?.save(finished)
        }
        startSyncLoop()
    }

    // MARK: - 러닝 조작 (RunView·워치 공용)

    @discardableResult
    func start(sessionID: UUID = UUID(), sendToWatch: Bool = true) -> Bool {
        guard ownerID != nil,
              session.state == .idle || session.state == .finished,
              session.locationAuthorization == .authorizedWhenInUse
                || session.locationAuthorization == .authorizedAlways else { return false }
        let usesWatchWorkout = sendToWatch ? watch.isReachable : true
        finishedRun = nil
        showsDiscardedRun = false
        takeoverMessage = nil   // 지난 러닝의 인계 안내가 새 러닝에서 뒤늦게 뜨지 않게
        session.start(sessionID: sessionID, healthManagedExternally: usesWatchWorkout)
        guard session.state == .running else { return false }
        lastWatchSnapshotAt = nil
        watchStartedAt = usesWatchWorkout ? Date() : nil
        guard sendToWatch, usesWatchWorkout else { return true }
        watch.sendCommand(.start, sessionID: sessionID)
        return true
    }

    func pause(sendToWatch: Bool = true) {
        session.pause()
        if sendToWatch { watch.sendCommand(.pause, sessionID: session.sessionID) }
    }

    func resume(sendToWatch: Bool = true) {
        session.resume()
        if sendToWatch { watch.sendCommand(.resume, sessionID: session.sessionID) }
    }

    /// 저장할 계정을 못 찾으면 false — 호출한 쪽이 알럿을 띄운다
    @discardableResult
    func finish(sendToWatch: Bool) -> Bool {
        guard let ownerID,
              session.state == .running || session.state == .paused else { return false }
        // 폰과 워치의 GPS/HealthKit 거리는 터널처럼 수신이 불안정한 구간에서 서로 달라질 수 있다.
        // 함께 기록한 러닝은 폰 저장값을 최종 기준으로 보내 두 화면이 같은 거리·시간으로 끝나게 한다.
        if sendToWatch {
            watch.sendCommand(
                .end,
                sessionID: session.sessionID,
                finalDistanceMeters: session.distanceMeters,
                finalElapsedSeconds: session.elapsedSeconds
            )
        }
        let run = session.finish(ownerID: ownerID, weightKg: weightKg, context: context)
        guard session.state == .finished else { return false }
        showsDiscardedRun = run == nil
        finishedRun = run
        watchStartedAt = nil
        lastWatchSnapshotAt = nil
        return true
    }

    /// 중단된 러닝을 기록으로 남긴다
    @discardableResult
    func saveRecovered(_ recovered: RecoveredRun) -> Bool {
        guard let ownerID else { return false }
        if RunSession.save(recovered, ownerID: ownerID, weightKg: weightKg, context: context) == nil {
            showsDiscardedRun = true
        }
        return true
    }

    // MARK: - 워치 수신

    private func handle(_ action: WorkoutSyncAction, remoteSessionID: UUID) {
        switch action {
        case .start:
            if session.state == .running || session.state == .paused {
                // 왜: 양쪽에서 따로 시작해 sessionID가 갈리면 이후 pause/end가 모두 버려진다. 폰 ID를 알려 맞춘다.
                // 폰이 담당 중이어도 워치를 끝내지 않는다 — 예전엔 .end 를 보내서 손목에서 시작한 워치가
                // 시작하자마자 멈추고 몇 초짜리 워크아웃만 남았다. 첫 스냅샷이 오면 apply 가 기록을 워치에 넘긴다.
                watch.sendCommand(.start, sessionID: session.sessionID)
                if session.state == .paused { watch.sendCommand(.pause, sessionID: session.sessionID) }
                return
            }
            // 저장할 계정이 없으면 아예 받지 않는다 — 받아 두면 .end에서 finish가 실패해
            // 세션이 running(GPS 켜진 채)에 갇히고, 알럿은 RunView에서만 뜨니 아무도 모른다.
            guard session.state == .idle || session.state == .finished, ownerID != nil else { return }
            if start(sessionID: remoteSessionID, sendToWatch: false) {
                showsWatchRun = true
            } else {
                watchStartError = "워치 러닝을 iPhone과 함께 기록하려면 iPhone 설정에서 RunCanvas의 위치 접근을 허용해주세요."
            }
        case .pause:
            guard remoteSessionID == session.sessionID else { return }
            pause(sendToWatch: false)
        case .resume:
            guard remoteSessionID == session.sessionID else { return }
            resume(sendToWatch: false)
        case .end:
            guard remoteSessionID == session.sessionID,
                  session.state == .running || session.state == .paused else { return }
            // 워치에서 종료한 경우에도 폰이 실제로 저장할 최종 수치를 다시 보내 준다.
            // 워치는 이 응답을 받는 즉시(또는 지연 배달된 뒤) 종료 화면을 같은 값으로 보정한다.
            watch.sendCommand(
                .end,
                sessionID: session.sessionID,
                finalDistanceMeters: session.distanceMeters,
                finalElapsedSeconds: session.elapsedSeconds
            )
            finish(sendToWatch: false)
        case .unavailable:
            guard remoteSessionID == session.sessionID else { return }
            takeOver("Apple Watch에서 운동을 시작하지 못해 iPhone 기록으로 전환했어요.")
        }
    }

    private func apply(_ snapshot: WatchWorkoutSnapshot) {
        guard snapshot.sessionID == session.sessionID else { return }
        lastWatchSnapshotAt = Date()
        guard session.state == .running || session.state == .paused else { return }
        if !session.healthManagedExternally {
            // 폰이 기록 중인데 워치가 같은 세션으로 살아 있다 — 시작 타임아웃 뒤 늦게 열렸거나 손목에서 직접 시작했다.
            // 워치를 끝내는 대신 HealthKit 기록을 워치에 넘긴다. "finished"는 여기서 안 듣는다 —
            // 인계 뒤 워치가 되쏘는 종료로 달리는 중인 러닝이 끝나면 안 되고, 진짜 종료는 .end 명령으로 온다.
            guard snapshot.state != "finished" else { return }
            session.joinWatchWorkout(distanceMeters: snapshot.distanceMeters)
            takeoverMessage = nil
        }
        session.recordWatchDistance(snapshot.distanceMeters)   // finish 전에 — 마지막 거리가 기록에 남게
        // 워치의 "finished" 스냅샷은 sendMessage라 .end(transferUserInfo)보다 먼저 온다. 여기서 바로 끝낸다.
        if snapshot.state == "finished" {
            finish(sendToWatch: false)
            return
        }
        guard let heartRate = snapshot.heartRate else { return }
        // 값이 같아도 매번 기록한다 — 바뀔 때만 담으면 심박 변동이 큰 구간으로 평균이 쏠린다
        session.recordHeartRate(heartRate)
    }

    /// 워치가 끝낸 러닝 요약. 폰이 실시간으로 못 받았어도(앱이 잠들어 있었어도) 여기서 기록이 된다.
    /// 경로는 비어 있고, 다음 `HealthImport` 가 건강 앱에서 읽어 채운다.
    private func save(_ finished: FinishedWatchWorkout) {
        guard let ownerID else { return }
        // 폰이 지금 이 러닝을 기록 중이면 곧 자기가 저장한다 — 겹쳐 만들지 않는다
        guard session.state != .running, session.state != .paused else { return }
        // WatchConnectivityService 가 델리게이트 콜백을 메인으로 넘겨 준다 (RunCoordinator 자체는 격리돼 있지 않다)
        MainActor.assumeIsolated {
            HealthImport.saveIfMissing(
                ImportedWorkout(
                    id: finished.workoutID, startedAt: finished.startedAt, endedAt: finished.endedAt,
                    distanceMeters: finished.distanceMeters, calories: finished.calories,
                    averageHeartRate: finished.averageHeartRate, maxHeartRate: finished.maxHeartRate, route: []
                ),
                ownerID: ownerID, context: context
            )
        }
    }

    // MARK: - 스냅샷 송신 + 워치 감시

    private func startSyncLoop() {
        syncTask?.cancel()
        syncTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.syncTick()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func syncTick() {
        guard session.state == .running || session.state == .paused else { return }
        if watch.isReachable {
            watch.sendSnapshot(
                sessionID: session.sessionID,
                state: session.state == .running ? "running" : "paused",
                elapsedSeconds: session.elapsedSeconds,
                distanceMeters: session.distanceMeters,
                heartRate: nil
            )
        }
        checkWatchAlive()
    }

    /// 워치가 .start 를 받고도 30초 안에 스냅샷을 안 보내면 워크아웃을 못 연 걸로 보고 폰이 심박 기록을 넘겨받는다.
    /// 워치를 끝내지는 않는다 — 늦게라도 열려 스냅샷이 오면 apply 가 기록을 다시 워치에 넘긴다.
    /// 러닝 중 무소식은 더 이상 인계 사유가 아니다. 예전엔 30초 끊기면 .discard 를 보냈는데, 블루투스가
    /// 잠깐 끊긴 것만으로 워치 워크아웃이 통째로 버려지고(건강 앱 기록 증발) 워치가 저 혼자 멈춰 보였다.
    private func checkWatchAlive() {
        guard session.healthManagedExternally, lastWatchSnapshotAt == nil, let watchStartedAt,
              Date().timeIntervalSince(watchStartedAt) > Self.watchStartTimeout else { return }
        takeOver("Apple Watch에서 운동이 시작되지 않아 iPhone 기록으로 전환했어요.")
    }

    private func takeOver(_ message: String) {
        guard session.healthManagedExternally else { return }
        session.takeOverHealthWorkout(since: lastWatchSnapshotAt ?? Date())
        watchStartedAt = nil
        takeoverMessage = message
    }
}
