import Foundation
import Combine
import WatchConnectivity

enum WorkoutSyncAction: String {
    case start
    case pause
    case resume
    case end
    case unavailable
}

struct WatchWorkoutSnapshot {
    let sessionID: UUID
    let state: String
    let elapsedSeconds: Int
    let distanceMeters: Double
    let heartRate: Double?
}

/// iPhone과 Apple Watch 사이의 러닝 명령·실시간 수치를 전달한다.
final class WatchConnectivityService: NSObject, ObservableObject {
    @Published private(set) var isPaired = false
    @Published private(set) var isWatchAppInstalled = false
    @Published private(set) var isReachable = false

    var onCommand: ((WorkoutSyncAction, UUID) -> Void)?
    var onSnapshot: ((WatchWorkoutSnapshot) -> Void)?

    private let session: WCSession?
    private var latestCommandTimestamp: TimeInterval = 0

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    /// 명령은 transferUserInfo — 워치가 잠깐 안 닿아도 큐에 쌓였다가 반드시 배달된다.
    /// (sendMessage로 보내면 isReachable false일 때 조용히 사라져서 워치 워크아웃이 안 끝났다)
    func sendCommand(_ action: WorkoutSyncAction, sessionID: UUID) {
        guard let session, session.activationState == .activated, session.isWatchAppInstalled else { return }
        session.transferUserInfo(commandMessage(action, sessionID: sessionID))
    }

    func sendSnapshot(
        sessionID: UUID,
        state: String,
        elapsedSeconds: Int,
        distanceMeters: Double,
        heartRate: Double?
    ) {
        var message: [String: Any] = [
            "kind": "snapshot",
            "sessionID": sessionID.uuidString,
            "state": state,
            "elapsedSeconds": elapsedSeconds,
            "distanceMeters": distanceMeters,
            "timestamp": Date().timeIntervalSince1970
        ]
        if let heartRate { message["heartRate"] = heartRate }
        send(message)   // 스냅샷은 유실돼도 다음 주기에 덮어써지니 sendMessage로 충분
    }

    private func commandMessage(_ action: WorkoutSyncAction, sessionID: UUID) -> [String: Any] {
        [
            "kind": "command",
            "action": action.rawValue,
            "sessionID": sessionID.uuidString,
            "timestamp": Date().timeIntervalSince1970
        ]
    }

    private func send(_ message: [String: Any]) {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    private func receive(_ message: [String: Any]) {
        guard let kind = message["kind"] as? String,
              let idString = message["sessionID"] as? String,
              let sessionID = UUID(uuidString: idString) else { return }

        if kind == "command",
           let rawAction = message["action"] as? String,
           let action = WorkoutSyncAction(rawValue: rawAction) {
            let timestamp = message["timestamp"] as? TimeInterval ?? 0
            guard timestamp > latestCommandTimestamp else { return }
            latestCommandTimestamp = timestamp
            onCommand?(action, sessionID)
            return
        }

        guard kind == "snapshot" else { return }
        onSnapshot?(WatchWorkoutSnapshot(
            sessionID: sessionID,
            state: message["state"] as? String ?? "idle",
            elapsedSeconds: message["elapsedSeconds"] as? Int ?? 0,
            distanceMeters: message["distanceMeters"] as? Double ?? 0,
            heartRate: message["heartRate"] as? Double
        ))
    }

    private func refreshState() {
        guard let session else { return }
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        isReachable = session.isReachable
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in self?.refreshState() }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in self?.refreshState() }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in self?.refreshState() }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.receive(message) }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async { [weak self] in self?.receive(userInfo) }
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        replyHandler(["received": true])
        DispatchQueue.main.async { [weak self] in self?.receive(message) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
