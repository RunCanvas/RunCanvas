import XCTest
import SwiftData
@testable import RunCanvas

final class RunSessionTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000_000)
    private let owner = UUID()

    private func makeSession() -> RunSession {
        RunSession(location: LocationService(), now: { self.now })
    }

    func testElapsedExcludesPausedTime() {
        let s = makeSession()
        s.start()
        now += 60
        s.pause()
        now += 30                                  // 정지 중 30초는 제외
        s.resume()
        now += 10
        XCTAssertEqual(s.elapsedSeconds, 70)
    }

    func testStateTransitions() {
        let s = makeSession()
        XCTAssertEqual(s.state, .idle)
        s.start();  XCTAssertEqual(s.state, .running)
        s.pause();  XCTAssertEqual(s.state, .paused)
        s.resume(); XCTAssertEqual(s.state, .running)
    }

    @MainActor
    func testFinishSavesRunForOwner() throws {
        let container = try ModelContainer(for: Run.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let s = makeSession()
        s.start()
        now += 120
        let run = s.finish(ownerID: owner, weightKg: 60, context: context)
        XCTAssertEqual(s.state, .finished)
        XCTAssertEqual(run.movingSeconds, 120)
        XCTAssertEqual(run.ownerID, owner)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Run>()).count, 1)
    }
}
