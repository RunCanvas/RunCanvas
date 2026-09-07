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
}
