import Foundation
import Combine
import WatchConnectivity

enum WorkoutSyncAction: String {
    case start
    case pause
    case resume
    case end
    /// 폰이 기록을 인계했다 — 저장하지 말고 버린다 (폰 쪽 WorkoutSyncAction 과 같은 목록이어야 한다)
    case discard
    case unavailable
}

struct PhoneWorkoutSnapshot {
    let sessionID: UUID
    let state: String
    let elapsedSeconds: Int
    let distanceMeters: Double
}

final class WatchConnectivityService: NSObject, ObservableObject {
    @Published private(set) var isReachable = false

    var onCommand: ((WorkoutSyncAction, UUID) -> Void)?
    var onSnapshot: ((PhoneWorkoutSnapshot) -> Void)?
    var onReachabilityChange: ((Bool) -> Void)?

    private let session: WCSession?
    private var latestCommandTimestamp: TimeInterval = 0
    /// 큐에 오래 남아 있던 시작 명령은 버린다(폰 쪽 WatchConnectivityService 와 같은 값)
    private static let maxStartCommandAge: TimeInterval = 120
    private static let allowedClockSkew: TimeInterval = 30

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    /// 명령은 transferUserInfo — 폰이 잠깐 안 닿아도 큐에 쌓였다가 반드시 배달된다
    func sendCommand(_ action: WorkoutSyncAction, sessionID: UUID) {
        let message: [String: Any] = [
            "kind": "command",
            "action": action.rawValue,
            "sessionID": sessionID.uuidString,
            "timestamp": Date().timeIntervalSince1970
        ]
        guard let session, session.activationState == .activated else { return }
        session.transferUserInfo(message)
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
            // 왜: transferUserInfo 는 상대가 안 닿아도 큐에 남았다가 다음에 앱이 켜질 때 배달된다.
            // 몇 시간 전 폰이 보낸 .start 가 그때 도착하면 워치가 갑자기 워크아웃을 시작한다.
            // .pause/.resume/.end 는 sessionID 가 걸러 주므로 시작 명령만 신선도를 본다.
            if action == .start, !Self.isFreshStartCommand(timestamp: timestamp) { return }
            latestCommandTimestamp = timestamp
            onCommand?(action, sessionID)
            return
        }

        guard kind == "snapshot" else { return }
        onSnapshot?(PhoneWorkoutSnapshot(
            sessionID: sessionID,
            state: message["state"] as? String ?? "idle",
            elapsedSeconds: message["elapsedSeconds"] as? Int ?? 0,
            distanceMeters: message["distanceMeters"] as? Double ?? 0
        ))
    }

    /// 시작 명령이 "지금 시작하라"는 뜻인지. 폰 쪽 WatchConnectivityService 와 같은 규칙이다.
    static func isFreshStartCommand(timestamp: TimeInterval, now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard timestamp.isFinite, timestamp > 0 else { return false }
        let age = now - timestamp
        return age >= -allowedClockSkew && age < maxStartCommandAge
    }

    private func updateReachability(_ reachable: Bool) {
        isReachable = reachable
        onReachabilityChange?(reachable)
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in self?.updateReachability(session.isReachable) }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in self?.updateReachability(session.isReachable) }
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

}
