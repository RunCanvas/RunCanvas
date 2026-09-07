import XCTest
import SwiftData
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

    // MARK: 워치가 보내는 요약 (폰 앱이 꺼져 있어도 transferUserInfo 로 배달된다)

    func testFinishedMessageParsesAndRejectsBrokenOnes() throws {
        let id = UUID()
        let message: [String: Any] = [
            "kind": "finished", "sessionID": UUID().uuidString, "workoutID": id.uuidString,
            "startedAt": base.timeIntervalSince1970,
            "endedAt": base.addingTimeInterval(1_800).timeIntervalSince1970,
            "distanceMeters": 5_000.0, "calories": 300.0, "averageHeartRate": 150.0
        ]
        let parsed = try XCTUnwrap(FinishedWatchWorkout(message))
        XCTAssertEqual(parsed.workoutID, id)
        XCTAssertEqual(parsed.distanceMeters, 5_000)
        XCTAssertEqual(parsed.averageHeartRate, 150)
        XCTAssertNil(parsed.maxHeartRate, "안 보낸 값은 nil 이어야 한다")

        XCTAssertNil(FinishedWatchWorkout(["workoutID": "not-a-uuid"]), "깨진 id 는 버린다")
        var backwards = message
        backwards["endedAt"] = base.addingTimeInterval(-10).timeIntervalSince1970
        XCTAssertNil(FinishedWatchWorkout(backwards), "끝이 시작보다 이르면 버린다")
    }

    @MainActor
    func testSaveIfMissingInsertsOnceThenSkips() throws {
        let container = try ModelContainer(for: Run.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let owner = UUID()
        let incoming = workout()

        XCTAssertTrue(HealthImport.saveIfMissing(incoming, ownerID: owner, context: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Run>()).count, 1)

        // 같은 요약이 다시 배달돼도(transferUserInfo 재시도) 기록이 두 개가 되면 안 된다
        XCTAssertFalse(HealthImport.saveIfMissing(incoming, ownerID: owner, context: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Run>()).count, 1)

        let saved = try XCTUnwrap(try context.fetch(FetchDescriptor<Run>()).first)
        XCTAssertEqual(saved.healthWorkoutID, incoming.id)
        XCTAssertTrue(saved.route.isEmpty, "요약엔 경로가 없다 — 다음 가져오기가 채운다")
    }
}

/// 가져오기 흐름 전체 — 조회부터 저장까지. 실기기 없이 확인할 수 있는 마지막 지점이다.
final class HealthImportFlowTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private struct FakeSource: WorkoutImporting {
        var workouts: [ImportedWorkout] = []
        var failure: Error?
        func requestAuthorization() async throws {}
        func importableWorkouts(since: Date) async throws -> [ImportedWorkout] {
            if let failure { throw failure }
            return workouts
        }
    }

    private struct Boom: Error {}

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Run.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func workout(_ id: UUID = UUID(), route: [RoutePoint] = []) -> ImportedWorkout {
        ImportedWorkout(id: id, startedAt: base, endedAt: base.addingTimeInterval(1_800),
                        distanceMeters: 5_000, calories: 300,
                        averageHeartRate: 150, maxHeartRate: 175, route: route)
    }

    private var somePoints: [RoutePoint] {
        [RoutePoint(latitude: 37.5, longitude: 127.0, timestamp: base),
         RoutePoint(latitude: 37.51, longitude: 127.01, timestamp: base.addingTimeInterval(60))]
    }

    @MainActor
    func testBringsInARunTheAppIsMissing() async throws {
        let context = try makeContext()
        let owner = UUID()
        let count = await HealthImport.importMissingRuns(
            context: context, ownerID: owner, health: FakeSource(workouts: [workout(route: somePoints)])
        )
        XCTAssertEqual(count, 1)
        let saved = try XCTUnwrap(try context.fetch(FetchDescriptor<Run>()).first)
        XCTAssertEqual(saved.distanceMeters, 5_000)
        XCTAssertEqual(saved.route.count, 2, "워치가 붙인 경로가 있으면 지도가 나와야 한다")
    }

    /// 워치 요약이 먼저 도착하면 경로 없는 기록이 생긴다. 다음 가져오기가 지도를 채워야 한다 —
    /// 안 그러면 그 러닝은 영영 지도가 없다.
    @MainActor
    func testFillsInTheMapForARunThatArrivedFromTheWatchSummary() async throws {
        let context = try makeContext()
        let owner = UUID()
        let id = UUID()
        context.insert(HealthImport.makeRun(from: workout(id), ownerID: owner))   // 경로 없음
        try context.save()

        let count = await HealthImport.importMissingRuns(
            context: context, ownerID: owner, health: FakeSource(workouts: [workout(id, route: somePoints)])
        )
        let runs = try context.fetch(FetchDescriptor<Run>())
        XCTAssertEqual(runs.count, 1, "같은 러닝이 두 개가 되면 안 된다")
        XCTAssertEqual(runs.first?.route.count, 2, "경로가 채워져야 한다")
        XCTAssertEqual(count, 0, "새로 만든 건 없다 — 채우기만 했다")
    }

    @MainActor
    func testDoesNotDuplicateARunThePhoneAlreadyRecorded() async throws {
        let context = try makeContext()
        let owner = UUID()
        // 폰이 기록한 러닝: workoutID 를 모른다(우리가 건강 앱에 따로 저장한 것)
        context.insert(Run(ownerID: owner, startedAt: base.addingTimeInterval(20),
                           endedAt: base.addingTimeInterval(1_800), distanceMeters: 5_000,
                           movingSeconds: 1_780, calories: 300))
        try context.save()

        let count = await HealthImport.importMissingRuns(
            context: context, ownerID: owner, health: FakeSource(workouts: [workout()])
        )
        XCTAssertEqual(count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Run>()).count, 1)
    }

    @MainActor
    func testCreatesNothingWhenHealthLookupFails() async throws {
        let context = try makeContext()
        let count = await HealthImport.importMissingRuns(
            context: context, ownerID: UUID(), health: FakeSource(failure: Boom())
        )
        XCTAssertEqual(count, 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Run>()).isEmpty)
    }

    /// 다른 계정 기록은 건드리지 않는다
    @MainActor
    func testImportsIntoTheSignedInAccountOnly() async throws {
        let context = try makeContext()
        let other = UUID()
        context.insert(Run(ownerID: other, startedAt: base, endedAt: base.addingTimeInterval(1_800),
                           distanceMeters: 5_000, movingSeconds: 1_800, calories: 300))
        try context.save()

        let mine = UUID()
        let count = await HealthImport.importMissingRuns(
            context: context, ownerID: mine, health: FakeSource(workouts: [workout()])
        )
        XCTAssertEqual(count, 1, "다른 계정 기록은 중복 판정에 쓰이면 안 된다")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Run>()).count, 2)
    }
}
