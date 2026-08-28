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

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func sendCommand(_ action: WorkoutSyncAction, sessionID: UUID) {
        let message: [String: Any] = [
            "kind": "command",
            "action": action.rawValue,
            "sessionID": sessionID.uuidString,
            "timestamp": Date().timeIntervalSince1970
        ]
        send(message)
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
        send(message)
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
        onSnapshot?(PhoneWorkoutSnapshot(
            sessionID: sessionID,
            state: message["state"] as? String ?? "idle",
            elapsedSeconds: message["elapsedSeconds"] as? Int ?? 0,
            distanceMeters: message["distanceMeters"] as? Double ?? 0
        ))
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

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        replyHandler(["received": true])
        DispatchQueue.main.async { [weak self] in self?.receive(message) }
    }

}
