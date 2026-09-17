import XCTest
@testable import RunCanvas

final class WatchConnectivityServiceTests: XCTestCase {
    func testImmediateAndQueuedStartAreHandledOnlyOnce() {
        let service = WatchConnectivityService()
        let id = UUID()
        var received: [UUID] = []
        service.onCommand = { action, sessionID in
            XCTAssertEqual(action, .start)
            received.append(sessionID)
        }
        let message = WatchConnectivityService.commandMessage(.start, sessionID: id)
        service.receive(message)
        service.receive(message)
        XCTAssertEqual(received, [id])
    }

    func testQueuedStartCannotRestartAfterNewerEnd() {
        let service = WatchConnectivityService()
        let id = UUID()
        let now = Date().timeIntervalSince1970
        var actions: [WorkoutSyncAction] = []
        service.onCommand = { action, _ in actions.append(action) }
        service.receive(WatchConnectivityService.commandMessage(.start, sessionID: id, timestamp: now - 1))
        service.receive(WatchConnectivityService.commandMessage(.end, sessionID: id, timestamp: now))
        service.receive(WatchConnectivityService.commandMessage(.start, sessionID: id, timestamp: now - 1))
        XCTAssertEqual(actions, [.start, .end])
    }

    func testEndCommandCarriesCanonicalPhoneMetrics() {
        let id = UUID()
        let message = WatchConnectivityService.commandMessage(
            .end,
            sessionID: id,
            finalDistanceMeters: 5_432.1,
            finalElapsedSeconds: 2_001,
            timestamp: 123
        )

        XCTAssertEqual(message["action"] as? String, "end")
        XCTAssertEqual(message["sessionID"] as? String, id.uuidString)
        XCTAssertEqual(message["finalDistanceMeters"] as? Double, 5_432.1)
        XCTAssertEqual(message["finalElapsedSeconds"] as? Int, 2_001)
    }

    func testStartCommandRejectsMissingStaleAndFarFutureTimestamps() {
        let now = 10_000.0
        XCTAssertFalse(WatchConnectivityService.isFreshStartCommand(timestamp: 0, now: now))
        XCTAssertFalse(WatchConnectivityService.isFreshStartCommand(timestamp: now - 120, now: now))
        XCTAssertFalse(WatchConnectivityService.isFreshStartCommand(timestamp: now + 31, now: now))
    }

    func testStartCommandAcceptsRecentTimestampAndSmallClockSkew() {
        let now = 10_000.0
        XCTAssertTrue(WatchConnectivityService.isFreshStartCommand(timestamp: now - 119, now: now))
        XCTAssertTrue(WatchConnectivityService.isFreshStartCommand(timestamp: now + 30, now: now))
    }

    /// 폰과 워치가 `WorkoutSyncAction` 을 각자 한 벌씩 들고 있다(워치 타깃이 폰 코드를 공유하지 않는다).
    /// 한쪽에만 case 를 추가하면 `WorkoutSyncAction(rawValue:)` 가 nil 을 내고 그 명령은 **아무 소리 없이** 버려진다.
    /// 공유 파일로 합치기 전까지(MY_TODO) 이 테스트가 그 어긋남을 잡는다.
    func testPhoneAndWatchShareTheSameCommandList() throws {
        let root = URL(fileURLWithPath: #filePath)     // .../RunCanvasTests/WatchConnectivityServiceTests.swift
            .deletingLastPathComponent().deletingLastPathComponent()

        func cases(in path: String) throws -> [String] {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            let body = try XCTUnwrap(source.components(separatedBy: "enum WorkoutSyncAction").dropFirst().first)
            let declaration = try XCTUnwrap(body.components(separatedBy: "\n}").first)
            return declaration.split(separator: "\n").compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("case ") else { return nil }
                return String(trimmed.dropFirst(5)).split(separator: " ").first.map(String.init)
            }
        }

        let phone = try cases(in: "RunCanvas/Services/WatchConnectivityService.swift")
        let watch = try cases(in: "RunCanvas Watch App/WatchConnectivityService.swift")
        XCTAssertFalse(phone.isEmpty, "폰 쪽 enum 을 못 읽었다")
        XCTAssertEqual(phone, watch, "폰·워치의 명령 목록이 다르다 — 한쪽 명령이 조용히 무시된다")
        XCTAssertFalse(phone.contains("discard"),
                       "워치 기록을 원격으로 버리는 명령은 다시 넣지 않는다 — 블루투스가 잠깐 끊긴 것만으로 워치 워크아웃이 통째로 사라졌다")
    }
}
