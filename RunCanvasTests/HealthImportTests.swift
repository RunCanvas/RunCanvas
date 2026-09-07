import XCTest
@testable import RunCanvas

/// 폰 앱이 꺼진 채 워치로 뛴 러닝을 건강 앱에서 가져온다. 같은 러닝을 두 번 만들지 않는 게 핵심이다.
final class HealthImportTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func workout(_ id: UUID = UUID(), offset: TimeInterval = 0, minutes: Double = 30,
                         meters: Double = 5_000, route: [RoutePoint] = []) -> ImportedWorkout {
        let start = base.addingTimeInterval(offset)
        return ImportedWorkout(id: id, startedAt: start, endedAt: start.addingTimeInterval(minutes * 60),
                               distanceMeters: meters, calories: 300,
                               averageHeartRate: 150, maxHeartRate: 175, route: route)
    }

    func testImportsWorkoutTheAppDoesNotHave() {
        let new = HealthImport.newWorkouts(from: [workout()], existing: [])
        XCTAssertEqual(new.count, 1)
    }

    /// 폰으로 뛴 러닝은 우리가 건강 앱에도 저장한다 — 그대로 가져오면 같은 러닝이 두 개가 된다.
    /// 예전 기록은 워크아웃 id 를 모르므로 시간 겹침으로 걸러야 한다.
    func testSkipsRunTheAppAlreadyHasEvenWithoutTheWorkoutID() {
        let existing = [ExistingRun(startedAt: base.addingTimeInterval(30),   // 30초 어긋난 같은 러닝
                                    endedAt: base.addingTimeInterval(1_800))]
        XCTAssertTrue(HealthImport.newWorkouts(from: [workout()], existing: existing).isEmpty)

        // 구간이 통째로 겹치는 경우도 (시작 시각 차이가 허용치를 넘더라도)
        let overlapping = [ExistingRun(startedAt: base.addingTimeInterval(-600),
                                       endedAt: base.addingTimeInterval(1_200))]
        XCTAssertTrue(HealthImport.newWorkouts(from: [workout()], existing: overlapping).isEmpty)
    }

    func testSkipsWorkoutAlreadyImportedByID() {
        let id = UUID()
        let existing = [ExistingRun(startedAt: .distantPast, endedAt: .distantPast, healthWorkoutID: id)]
        XCTAssertTrue(HealthImport.newWorkouts(from: [workout(id)], existing: existing).isEmpty)
    }

    /// 잘못 눌러 생긴 조각까지 기록으로 만들면 통계·뱃지가 흐려진다
    func testSkipsTooShortOrTooCloseWorkouts() {
        XCTAssertTrue(HealthImport.newWorkouts(from: [workout(minutes: 0.5)], existing: []).isEmpty)
        XCTAssertTrue(HealthImport.newWorkouts(from: [workout(meters: 50)], existing: []).isEmpty)
    }

    /// 다른 날 뛴 러닝은 서로 다른 기록이다
    func testKeepsSeparateRunsOnDifferentDays() {
        let yesterday = workout(offset: -86_400)
        let existing = [ExistingRun(startedAt: base, endedAt: base.addingTimeInterval(1_800))]
        XCTAssertEqual(HealthImport.newWorkouts(from: [yesterday], existing: existing).count, 1)
    }

    func testMakeRunCarriesRouteAndWorkoutID() {
        let id = UUID()
        let owner = UUID()
        let points = [RoutePoint(latitude: 37.5, longitude: 127.0, timestamp: base),
                      RoutePoint(latitude: 37.51, longitude: 127.01, timestamp: base.addingTimeInterval(60))]
        let run = HealthImport.makeRun(from: workout(id, route: points), ownerID: owner)
        XCTAssertEqual(run.healthWorkoutID, id)
        XCTAssertEqual(run.ownerID, owner)
        XCTAssertEqual(run.route.count, 2, "워치가 붙인 경로가 있으면 지도가 나와야 한다")
        XCTAssertEqual(run.distanceMeters, 5_000)
        XCTAssertEqual(run.movingSeconds, 1_800)
        XCTAssertEqual(run.averageHeartRate, 150)
    }
}
