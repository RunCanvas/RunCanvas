import Foundation
import Combine
import WatchConnectivity

enum WorkoutSyncAction: String {
    case start
    case pause
    case resume
    case end
    /// 폰이 기록을 인계했다 — 워치는 진행 중인 워크아웃을 저장하지 말고 버린다.
    /// (`.end` 로는 "사용자가 끝냈다"와 구분이 안 돼 건강 앱에 짧은 중복 워크아웃이 남았다)
    case discard
    case unavailable
}

/// 워치가 러닝을 끝내며 보내는 요약. 스냅샷과 달리 transferUserInfo 로 가므로
/// 폰 앱이 꺼져 있어도 큐에 남았다가 배달된다 — 건강 앱 권한이 없어도 기록이 남는 길.
struct FinishedWatchWorkout {
    let workoutID: UUID
    let startedAt: Date
    let endedAt: Date
    let distanceMeters: Double
    let calories: Double
    let averageHeartRate: Double?
    let maxHeartRate: Double?

    init?(_ message: [String: Any]) {
        guard let idString = message["workoutID"] as? String, let workoutID = UUID(uuidString: idString),
              let start = message["startedAt"] as? TimeInterval,
              let end = message["endedAt"] as? TimeInterval, end > start else { return nil }
        self.workoutID = workoutID
        self.startedAt = Date(timeIntervalSince1970: start)
        self.endedAt = Date(timeIntervalSince1970: end)
        self.distanceMeters = message["distanceMeters"] as? Double ?? 0
        self.calories = message["calories"] as? Double ?? 0
        self.averageHeartRate = message["averageHeartRate"] as? Double
        self.maxHeartRate = message["maxHeartRate"] as? Double
    }
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
    /// 워치가 끝낸 러닝 요약 — 폰이 실시간으로 못 받았어도 기록으로 남긴다
    var onFinishedWorkout: ((FinishedWatchWorkout) -> Void)?

    private let session: WCSession?
    private var latestCommandTimestamp: TimeInterval = 0
    private static let maxStartCommandAge: TimeInterval = 120
    private static let allowedClockSkew: TimeInterval = 30

    override init() {
        session = WCSession.isSupported() ? .default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    /// 큐로 유실을 막고, 연결 중에는 같은 명령을 즉시 전송한다. 수신 타임스탬프로 중복을 거른다.
    func sendCommand(
        _ action: WorkoutSyncAction,
        sessionID: UUID,
        finalDistanceMeters: Double? = nil,
        finalElapsedSeconds: Int? = nil
    ) {
        guard let session, session.activationState == .activated, session.isWatchAppInstalled else { return }
        let message = Self.commandMessage(
            action,
            sessionID: sessionID,
            finalDistanceMeters: finalDistanceMeters,
            finalElapsedSeconds: finalElapsedSeconds
        )
        session.transferUserInfo(message)
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        }
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

    static func commandMessage(
        _ action: WorkoutSyncAction,
        sessionID: UUID,
        finalDistanceMeters: Double? = nil,
        finalElapsedSeconds: Int? = nil,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) -> [String: Any] {
        var message: [String: Any] = [
            "kind": "command",
            "action": action.rawValue,
            "sessionID": sessionID.uuidString,
            "timestamp": timestamp
        ]
        if let finalDistanceMeters { message["finalDistanceMeters"] = finalDistanceMeters }
        if let finalElapsedSeconds { message["finalElapsedSeconds"] = finalElapsedSeconds }
        return message
    }

    private func send(_ message: [String: Any]) {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    func receive(_ message: [String: Any]) {
        guard let kind = message["kind"] as? String,
              let idString = message["sessionID"] as? String,
              let sessionID = UUID(uuidString: idString) else { return }

        if kind == "command",
           let rawAction = message["action"] as? String,
           let action = WorkoutSyncAction(rawValue: rawAction) {
            let timestamp = message["timestamp"] as? TimeInterval ?? 0
            guard timestamp.isFinite, timestamp > latestCommandTimestamp else { return }
            if action == .start {
                // transferUserInfo의 오래된 start는 몇 시간 뒤 재생될 수 있다. 타임스탬프 없는 구버전 메시지도 안전하게 버린다.
                guard Self.isFreshStartCommand(timestamp: timestamp) else { return }
            }
            latestCommandTimestamp = timestamp
            onCommand?(action, sessionID)
            return
        }

        if kind == "finished", let finished = FinishedWatchWorkout(message) {
            onFinishedWorkout?(finished)
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

    static func isFreshStartCommand(timestamp: TimeInterval, now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard timestamp.isFinite, timestamp > 0 else { return false }
        let age = now - timestamp
        return age >= -allowedClockSkew && age < maxStartCommandAge
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
