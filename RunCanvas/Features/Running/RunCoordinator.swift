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

    /// 세션이 만료돼 auth.userID가 사라져도 기록을 잃지 않도록 마지막 계정을 들고 있는다
    var ownerID: UUID? {
        get { UserDefaults.standard.string(forKey: Self.ownerKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: Self.ownerKey) }
    }

    private static let ownerKey = "lastOwnerID"
    /// 워치가 .start를 받고도 이 시간 안에 스냅샷을 안 보내면 워크아웃을 못 연 걸로 본다
    private static let watchStartTimeout: TimeInterval = 15
    /// 러닝 중 스냅샷이 이만큼 끊기면 워치가 벗겨진 걸로 본다
    private static let watchDropTimeout: TimeInterval = 30

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
        if sendToWatch { watch.sendCommand(.end, sessionID: session.sessionID) }
        guard let run = session.finish(ownerID: ownerID, weightKg: weightKg, context: context) else { return false }
        finishedRun = run
        watchStartedAt = nil
        lastWatchSnapshotAt = nil
        return true
    }

    /// 중단된 러닝을 기록으로 남긴다
    @discardableResult
    func saveRecovered(_ recovered: RecoveredRun) -> Bool {
        guard let ownerID else { return false }
        RunSession.save(recovered, ownerID: ownerID, weightKg: weightKg, context: context)
        return true
    }

    // MARK: - 워치 수신

    private func handle(_ action: WorkoutSyncAction, remoteSessionID: UUID) {
        switch action {
        case .start:
            if session.state == .running || session.state == .paused {
                // 왜: 양쪽에서 따로 시작해 sessionID가 갈리면 이후 pause/end가 모두 버려진다.
                // 원래 워치가 담당하던 세션이면 폰 ID를 다시 알려 맞추고, 폰이 담당 중이면
                // 늦게 시작한 워치를 끝내 HealthKit에 워크아웃 두 개가 저장되지 않게 한다.
                if session.healthManagedExternally {
                    watch.sendCommand(.start, sessionID: session.sessionID)
                } else {
                    watch.sendCommand(.end, sessionID: remoteSessionID)
                }
                return
            }
            // 저장할 계정이 없으면 아예 받지 않는다 — 받아 두면 .end에서 finish가 실패해
            // 세션이 running(GPS 켜진 채)에 갇히고, 알럿은 RunView에서만 뜨니 아무도 모른다.
            guard session.state == .idle || session.state == .finished, ownerID != nil else { return }
            _ = start(sessionID: remoteSessionID, sendToWatch: false)
        case .pause:
            guard remoteSessionID == session.sessionID else { return }
            pause(sendToWatch: false)
        case .resume:
            guard remoteSessionID == session.sessionID else { return }
            resume(sendToWatch: false)
        case .end:
            guard remoteSessionID == session.sessionID,
                  session.state == .running || session.state == .paused else { return }
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
        // 폰이 인계한 뒤엔 워치 스냅샷을 아예 듣지 않는다. takeOver가 보낸 .end로 워치가 끝나면서
        // 같은 sessionID로 "finished"를 되쏘는데, 그걸 받으면 아직 달리는 중인 폰 러닝까지 끝나 버린다.
        // 심박도 폰 스트림과 이중으로 쌓여 평균·최대가 틀어진다.
        guard session.healthManagedExternally else { return }
        // 워치의 "finished" 스냅샷은 sendMessage라 .end(transferUserInfo)보다 먼저 온다.
        // 여기서 바로 끝내야 .end가 30초 넘게 늦어도 checkWatchAlive가 "연결 끊김"으로 오판해
        // 폰 심박 스트림을 켜고 HealthKit 워크아웃을 한 번 더 저장하는 일이 없다.
        if snapshot.state == "finished" {
            finish(sendToWatch: false)
            return
        }
        guard let heartRate = snapshot.heartRate else { return }
        // 값이 같아도 매번 기록한다 — 바뀔 때만 담으면 심박 변동이 큰 구간으로 평균이 쏠린다
        session.recordHeartRate(heartRate)
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

    /// 워치가 워크아웃을 못 열었거나(15초 무소식) 러닝 중 끊겼으면(30초 무소식) 폰이 기록을 넘겨받는다.
    /// sendCommand의 "전달됨"만 믿으면 워치에서 start가 실패했을 때 아무도 심박을 기록하지 않는다.
    private func checkWatchAlive() {
        guard session.healthManagedExternally, let watchStartedAt else { return }
        let since = lastWatchSnapshotAt ?? watchStartedAt
        let timeout = lastWatchSnapshotAt == nil ? Self.watchStartTimeout : Self.watchDropTimeout
        guard Date().timeIntervalSince(since) > timeout else { return }
        takeOver(lastWatchSnapshotAt == nil
                 ? "Apple Watch에서 운동이 시작되지 않아 iPhone 기록으로 전환했어요."
                 : "Apple Watch 연결이 끊겨 iPhone 기록으로 전환했어요.")
    }

    private func takeOver(_ message: String) {
        guard session.healthManagedExternally else { return }
        // 워치 start가 늦게 도착하거나 잠깐 끊긴 뒤에도 둘 다 HealthKit 워크아웃을 저장하지 않게
        // 같은 sessionID의 종료를 큐에 남긴다. 워치의 start-await 중 end 유실은 pendingEnd가 막는다.
        watch.sendCommand(.end, sessionID: session.sessionID)
        session.takeOverHealthWorkout(since: lastWatchSnapshotAt ?? Date())
        watchStartedAt = nil
        takeoverMessage = message
    }
}
