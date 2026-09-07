import XCTest
@testable import RunCanvas

final class WatchConnectivityServiceTests: XCTestCase {
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
        XCTAssertTrue(phone.contains("discard"), "인계 시 워치 기록을 버리는 명령이 빠졌다")
    }
}
