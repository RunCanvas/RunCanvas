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
    /// 그대로 저장하면 페이스가 00'00"으로 찍힌다.
    func testZeroDurationIsDiscardedEvenWithDistance() {
        XCTAssertFalse(RunSavePolicy.shouldSave(distanceMeters: 8_000, seconds: 0))
        XCTAssertTrue(RunSavePolicy.shouldSave(distanceMeters: 8_000, seconds: 1))
    }

    func testPhoneAndWatchUseIdenticalPolicy() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
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
