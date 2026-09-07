import XCTest
@testable import RunCanvas

/// 서버 삭제 대기 목록. 여기가 비면 지운 기록이 다음 다운로드에서 되살아나고,
/// 계정 필터가 틀리면 다른 계정 아래에서 지우려다 RLS에 막혀 목록이 영영 안 비워진다.
final class SyncServiceTests: XCTestCase {
    private var backup: [SyncService.PendingDelete] = []

    @MainActor
    override func setUp() {
        super.setUp()
        backup = SyncService.pendingDeletes
        SyncService.pendingDeletes = []
    }

    @MainActor
    override func tearDown() {
        SyncService.pendingDeletes = backup
        super.tearDown()
    }

    @MainActor
    func testPendingDeletesSurviveRelaunchAndStayPerOwner() {
        let owner = UUID(), other = UUID()
        let mine = UUID()
        SyncService.pendingDeletes = [
            .init(ownerID: owner, runID: mine),
            .init(ownerID: other, runID: UUID())
        ]

        // UserDefaults 왕복 — 앱을 껐다 켜도 남아야 한다
        XCTAssertEqual(SyncService.pendingDeletes.count, 2)
        XCTAssertEqual(SyncService.pendingDeletes(for: owner), [mine])
        XCTAssertTrue(SyncService.pendingDeletes(for: UUID()).isEmpty)
    }

    @MainActor
    func testEmptyQueueDecodesWhenNothingWasSaved() {
        UserDefaults.standard.removeObject(forKey: "pendingRemoteDeletesV2")
        XCTAssertTrue(SyncService.pendingDeletes.isEmpty)
        // 깨진 값이 남아 있어도 크래시 대신 빈 목록 (버전 올리기 전 데이터)
        UserDefaults.standard.set(Data("not json".utf8), forKey: "pendingRemoteDeletesV2")
        XCTAssertTrue(SyncService.pendingDeletes.isEmpty)
    }
}
