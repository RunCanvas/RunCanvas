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
