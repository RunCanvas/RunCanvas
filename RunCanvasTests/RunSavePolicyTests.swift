import XCTest
import SwiftData
@testable import RunCanvas

final class RunSavePolicyTests: XCTestCase {
    func testDistanceBoundary() {
        for meters in [0.0, 49.99, 50, -1, .nan, .infinity] {
            XCTAssertFalse(RunSavePolicy.shouldSave(distanceMeters: meters))
        }
        XCTAssertTrue(RunSavePolicy.shouldSave(distanceMeters: 50.01))
    }

    /// 거리는 워치에서 한 번에 들어올 수 있어 "거리는 있는데 시간이 0"이 실제로 만들어진다.
    /// 그 기록을 **버리지는 않는다** — 실제로 뛴 거리를 잃는 쪽이 더 나쁘다.
    /// 대신 페이스가 00'00"으로 찍히지 않게 nil 을 낸다.
    func testZeroDurationKeepsRunButHasNoPace() {
        XCTAssertTrue(RunSavePolicy.shouldSave(distanceMeters: 8_000))
        XCTAssertNil(RunMath.paceSecondsPerKm(distanceMeters: 8_000, seconds: 0))
        XCTAssertEqual(RunMath.formatPace(RunMath.paceSecondsPerKm(distanceMeters: 8_000, seconds: 0)), "--'--\"")
        XCTAssertNotNil(RunMath.paceSecondsPerKm(distanceMeters: 8_000, seconds: 1))
    }

    func testPhoneAndWatchUseIdenticalPolicy() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        // 소스 파일을 직접 읽으므로 맥 파일시스템이 필요하다 — 실기기에서는 그 경로가 없다.
        try XCTSkipUnless(FileManager.default.fileExists(atPath: root.path),
                          "소스 대조 테스트는 시뮬레이터에서만 의미가 있다")
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("RunCanvas/Models/RunSavePolicy.swift"), encoding: .utf8),
            try String(contentsOf: root.appendingPathComponent("RunCanvas Watch App/RunSavePolicy.swift"), encoding: .utf8)
        )
    }

    @MainActor
    func testStationaryRunIsDiscardedAtAnyDurationAndCanRestart() throws {
        let container = try ModelContainer(for: Run.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        var now = Date()
        let session = RunSession(now: { now })
        let watch = WatchConnectivityService()
        let coordinator = RunCoordinator(watch: watch, context: container.mainContext, session: session)
        let previousOwner = coordinator.ownerID
        defer { coordinator.ownerID = previousOwner }
        coordinator.ownerID = UUID()
        for seconds in [30.0, 60, 600] {
            session.start()
            now += seconds
            XCTAssertTrue(coordinator.finish(sendToWatch: false))
            XCTAssertEqual(session.state, .finished)
            XCTAssertNil(coordinator.finishedRun)
            XCTAssertTrue(coordinator.showsDiscardedRun)
            XCTAssertNil(RunSession.recoverable())
            XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<Run>()).isEmpty)
        }
    }

    @MainActor
    func testRecoveryDoesNotRestoreDiscardedDistance() throws {
        let container = try ModelContainer(for: Run.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let recovered = RecoveredRun(sessionID: UUID(), startedAt: Date(), accumulated: 600, distanceMeters: 50, route: [])
        XCTAssertNil(RunSession.save(recovered, ownerID: UUID(), weightKg: 60, context: container.mainContext))
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<Run>()).isEmpty)
    }
}
