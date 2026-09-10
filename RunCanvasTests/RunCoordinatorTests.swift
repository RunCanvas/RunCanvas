import XCTest
import SwiftData
@testable import RunCanvas

final class RunCoordinatorTests: XCTestCase {
    /// 폰이 기록을 인계받은 뒤(워치 무응답) 워치가 되쏘는 "finished" 스냅샷은 무시한다 —
    /// 그대로 받으면 아직 달리는 중인 사용자의 러닝이 저 혼자 끝나 버린다.
    /// 반대로 워치가 같은 세션으로 살아서 "running"을 보내면 기록을 다시 워치에 넘긴다 —
    /// 예전엔 .discard 로 워치를 끝내 버려서 워치가 혼자 멈추고 건강 앱 기록이 사라졌다.
    @MainActor
    func testSnapshotsAfterTakeOverIgnoreFinishedButRejoinRunningWatch() throws {
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
        XCTAssertFalse(session.healthManagedExternally)
        XCTAssertEqual(session.heartRateSamples, [])

        watch.onSnapshot?(WatchWorkoutSnapshot(
            sessionID: id, state: "running", elapsedSeconds: 31, distanceMeters: 105, heartRate: 152
        ))
        XCTAssertTrue(session.healthManagedExternally, "워치가 살아 있으면 기록을 다시 넘긴다")
        XCTAssertEqual(session.heartRateSamples, [152])
        XCTAssertEqual(session.distanceMeters, 105, "폰이 센 게 없으면(0) 워치 누적이 맞다")

        watch.onSnapshot?(WatchWorkoutSnapshot(
            sessionID: id, state: "running", elapsedSeconds: 40, distanceMeters: 130, heartRate: 150
        ))
        XCTAssertEqual(session.distanceMeters, 130, accuracy: 0.001)
    }

    /// 폰 단독으로 달리다 손목에서 워치를 시작하면 워치를 끝내지 않고 합류시킨다.
    /// 예전엔 .end 를 보내서 워치가 시작하자마자 멈췄다.
    @MainActor
    func testWatchStartedDuringPhoneOnlyRunJoinsInsteadOfBeingEnded() throws {
        let (coordinator, session, watch) = try makeCoordinator()
        let previousOwner = coordinator.ownerID
        defer { coordinator.ownerID = previousOwner }
        coordinator.ownerID = UUID()

        session.start(healthManagedExternally: false)
        watch.onCommand?(.start, UUID())                // 워치가 제 ID로 시작을 알린다 (폰은 .start 로 ID를 맞춰 준다)
        XCTAssertEqual(session.state, .running)
        XCTAssertFalse(session.healthManagedExternally) // 첫 스냅샷 전까지는 폰이 기록

        watch.onSnapshot?(WatchWorkoutSnapshot(
            sessionID: session.sessionID, state: "running", elapsedSeconds: 2, distanceMeters: 3, heartRate: 140
        ))
        XCTAssertTrue(session.healthManagedExternally)
        XCTAssertEqual(session.heartRateSamples, [140])
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

    /// 거리는 워치의 HealthKit 값(GPS+걸음 융합)이 진실이다. 폰 GPS 체인을 쓰면 터널·고가 밑에서 얼어붙고,
    /// 건강 앱에 남는 워치 기록과 폰 기록이 어긋난다.
    @MainActor
    func testWatchDistanceIsRecordedWhileWatchOwnsWorkout() throws {
        let (coordinator, session, watch) = try makeCoordinator()
        let previousOwner = coordinator.ownerID
        defer { coordinator.ownerID = previousOwner }
        coordinator.ownerID = UUID()

        let id = UUID()
        session.start(sessionID: id, healthManagedExternally: true)

        watch.onSnapshot?(WatchWorkoutSnapshot(
            sessionID: id, state: "running", elapsedSeconds: 10, distanceMeters: 40, heartRate: nil
        ))
        XCTAssertEqual(session.distanceMeters, 40)

        watch.onSnapshot?(WatchWorkoutSnapshot(
            sessionID: id, state: "finished", elapsedSeconds: 20, distanceMeters: 80, heartRate: nil
        ))
        XCTAssertEqual(coordinator.finishedRun?.distanceMeters, 80, "마지막 스냅샷 거리가 기록에 남아야 한다")
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
