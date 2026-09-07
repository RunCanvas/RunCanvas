import XCTest
import SwiftData
@testable import RunCanvas

/// 폰이 기록을 인계받은 뒤(워치 무응답·연결 끊김) 워치가 뒤늦게 되쏘는 스냅샷을 무시하는지.
/// takeOver는 워치에 .end를 보내고, 워치는 끝나면서 같은 sessionID로 "finished"를 되쏜다 —
/// 그걸 그대로 받으면 아직 달리는 중인 사용자의 러닝이 저 혼자 끝나 버린다.
final class RunCoordinatorTests: XCTestCase {
    @MainActor
    func testSnapshotsAfterTakeOverDoNotEndRunOrDoubleCountHeartRate() throws {
        let container = try ModelContainer(
            for: Run.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let watch = WatchConnectivityService()
        let session = RunSession(location: LocationService())
        let coordinator = RunCoordinator(watch: watch, context: context, session: session)
        let previousOwner = coordinator.ownerID
        defer { coordinator.ownerID = previousOwner }   // ownerID는 UserDefaults에 남는다
        coordinator.ownerID = UUID()                    // 없으면 finish가 실패해 버그가 가려진다

        let id = UUID()
        session.start(sessionID: id, healthManagedExternally: true)

        watch.onCommand?(.unavailable, id)              // 워치가 워크아웃을 못 열어 폰이 인계
        XCTAssertFalse(session.healthManagedExternally)

        watch.onSnapshot?(WatchWorkoutSnapshot(
            sessionID: id, state: "finished", elapsedSeconds: 30, distanceMeters: 100, heartRate: 150
        ))
        XCTAssertEqual(session.state, .running)         // 사용자는 아직 달리는 중이다

        watch.onSnapshot?(WatchWorkoutSnapshot(
            sessionID: id, state: "running", elapsedSeconds: 31, distanceMeters: 105, heartRate: 152
        ))
        XCTAssertEqual(session.heartRateSamples, [])    // 심박은 폰 스트림만 담는다
    }

    /// 반대쪽 — 워치가 워크아웃을 들고 있는 정상 경로에서는 스냅샷이 실제로 반영돼야 한다.
    /// 위 테스트의 guard 를 너무 넓게 잡으면 워치 심박·종료가 통째로 죽는데, 그때 아무도 안 깨진다.
    @MainActor
    func testWatchSnapshotsRecordHeartRateAndFinishWhileWatchOwnsWorkout() throws {
        let (coordinator, session, watch) = try makeCoordinator()
        let previousOwner = coordinator.ownerID
        defer { coordinator.ownerID = previousOwner }
        coordinator.ownerID = UUID()

        let id = UUID()
        session.start(sessionID: id, healthManagedExternally: true)

        watch.onSnapshot?(WatchWorkoutSnapshot(
            sessionID: id, state: "running", elapsedSeconds: 10, distanceMeters: 40, heartRate: 148
        ))
        XCTAssertEqual(session.heartRateSamples, [148])

        watch.onSnapshot?(WatchWorkoutSnapshot(
            sessionID: id, state: "finished", elapsedSeconds: 20, distanceMeters: 80, heartRate: 150
        ))
        XCTAssertEqual(session.state, .finished, "워치가 끝냈으면 폰도 끝나야 한다")
        XCTAssertNotNil(coordinator.finishedRun, "결과 화면에 띄울 기록이 남아야 한다")
    }

    /// 다른 세션의 명령·스냅샷은 무시한다 — 지난 러닝의 큐가 늦게 배달돼도 지금 러닝을 건드리지 않게
    @MainActor
    func testCommandsAndSnapshotsForAnotherSessionAreIgnored() throws {
        let (coordinator, session, watch) = try makeCoordinator()
        let previousOwner = coordinator.ownerID
        defer { coordinator.ownerID = previousOwner }
        coordinator.ownerID = UUID()

        let id = UUID()
        session.start(sessionID: id, healthManagedExternally: true)

        watch.onCommand?(.pause, UUID())
        XCTAssertEqual(session.state, .running)

        watch.onSnapshot?(WatchWorkoutSnapshot(
            sessionID: UUID(), state: "finished", elapsedSeconds: 9, distanceMeters: 9, heartRate: 160
        ))
        XCTAssertEqual(session.state, .running)
        XCTAssertEqual(session.heartRateSamples, [])

        watch.onCommand?(.end, id)
        XCTAssertEqual(session.state, .finished, "같은 세션의 종료는 받아야 한다")
    }

    @MainActor
    private func makeCoordinator() throws -> (RunCoordinator, RunSession, WatchConnectivityService) {
        let container = try ModelContainer(
            for: Run.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let watch = WatchConnectivityService()
        let session = RunSession(location: LocationService())
        return (RunCoordinator(watch: watch, context: ModelContext(container), session: session), session, watch)
    }
}
