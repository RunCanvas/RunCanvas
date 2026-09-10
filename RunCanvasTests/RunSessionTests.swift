import XCTest
import SwiftData
import CoreLocation
@testable import RunCanvas

final class RunSessionTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000_000)
    private let owner = UUID()

    private final class HealthSpy: HealthServicing {
        var didStartStream = false
        var streamStartDates: [Date] = []
        var didStopStream = false
        var savedSummary: WorkoutSummary?
        var onSample: ((Double) -> Void)?
        var saveExpectation: XCTestExpectation?

        func requestAuthorization() async throws {}

        func startHeartRateStream(since startDate: Date, onSample: @escaping (Double) -> Void) {
            didStartStream = true
            streamStartDates.append(startDate)
            self.onSample = onSample
        }

        func stopHeartRateStream() {
            didStopStream = true
        }

        func saveWorkout(_ summary: WorkoutSummary) async throws {
            savedSummary = summary
            saveExpectation?.fulfill()
        }
    }

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

    func testHealthStreamUpdatesCurrentAndSummaryHeartRate() {
        let health = HealthSpy()
        let s = RunSession(location: LocationService(), health: health, now: { self.now })

        s.start()
        health.onSample?(140)
        health.onSample?(160)

        XCTAssertTrue(health.didStartStream)
        XCTAssertEqual(s.heartRate, 160)
        XCTAssertEqual(s.heartRateSamples, [140, 160])
    }

    @MainActor
    func testWatchManagedWorkoutSkipsPhoneHealthWorkout() throws {
        let container = try ModelContainer(for: Run.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let health = HealthSpy()
        let s = RunSession(location: LocationService(), health: health, now: { self.now })

        s.start(healthManagedExternally: true)
        s.recordHeartRate(152)
        _ = s.finish(ownerID: owner, weightKg: 60, context: context)

        XCTAssertFalse(health.didStartStream)
        XCTAssertTrue(health.didStopStream)
        XCTAssertNil(health.savedSummary)
    }

    func testWatchTakeoverStartsPhoneHeartRateAtTakeoverTime() {
        let health = HealthSpy()
        let s = RunSession(location: LocationService(), health: health, now: { self.now })
        s.start(healthManagedExternally: true)
        let takeover = now.addingTimeInterval(30)

        s.takeOverHealthWorkout(since: takeover)

        XCTAssertFalse(s.healthManagedExternally)
        XCTAssertEqual(health.streamStartDates, [takeover])
    }

    /// 폰 단독으로 달리다 워치가 합류하면: 폰 심박 스트림을 끄고, 거리는 폰 값에서 잇고,
    /// 끝낼 때 HealthKit 워크아웃을 폰이 저장하지 않는다 (워치가 저장한다 — 둘 다 저장하면 건강 앱에 두 개)
    @MainActor
    func testJoinWatchWorkoutHandsOverHeartRateDistanceAndHealthWorkout() throws {
        let container = try ModelContainer(for: Run.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let health = HealthSpy()
        let s = RunSession(location: LocationService(), health: health, now: { self.now })
        s.start()
        XCTAssertTrue(health.didStartStream)

        s.joinWatchWorkout(distanceMeters: 40)       // 워치는 이미 40m를 셌다
        XCTAssertTrue(s.healthManagedExternally)
        XCTAssertTrue(health.didStopStream)
        XCTAssertEqual(s.distanceMeters, 40, "폰이 센 게 없으면(0) 워치 누적이 맞다")
        s.recordWatchDistance(100)
        XCTAssertEqual(s.distanceMeters, 100)

        _ = s.finish(ownerID: owner, weightKg: 60, context: context)
        XCTAssertNil(health.savedSummary, "워크아웃은 워치가 저장한다")
    }

    /// 폰이 먼저 시작하고 워치가 늦게 열리면 워치 거리엔 앞 구간이 빠져 있다 — 폰이 센 거리를 지키고 워치 증가분만 잇는다
    func testLateWatchKeepsPhoneHeadDistance() {
        let location = LocationService()
        let s = RunSession(location: location, now: { self.now })
        s.start(healthManagedExternally: true)
        location.locationManager(CLLocationManager(), didUpdateLocations: [fix(37.5445, at: -3), fix(37.5446, at: -2), fix(37.5447, at: -1)])
        XCTAssertEqual(s.distanceMeters, 22.2, accuracy: 0.5, "워치 스냅샷 전엔 폰 GPS")

        s.recordWatchDistance(5)                                 // 워치는 방금 열려 5m
        XCTAssertEqual(s.distanceMeters, 22.2, accuracy: 0.5, "뒤로 점프하지 않는다")
        s.recordWatchDistance(35)
        XCTAssertEqual(s.distanceMeters, 52.2, accuracy: 0.5)
    }

    /// 워치가 먼저 시작해 폰이 늦게 합류하면 폰은 앞 구간을 못 봤다 — 워치 누적을 그대로 쓴다
    func testWatchFirstUsesWatchTotal() {
        let s = makeSession()
        s.start(healthManagedExternally: true)
        s.recordWatchDistance(200)
        XCTAssertEqual(s.distanceMeters, 200)
    }

    /// 위도 0.0001° ≈ 11.1m
    private func fix(_ lat: Double, at seconds: TimeInterval) -> CLLocation {
        CLLocation(coordinate: .init(latitude: lat, longitude: 127.0374), altitude: 0,
                   horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date(timeIntervalSinceNow: seconds))
    }

    /// 워치가 끊겨 폰이 이어받아도 거리가 뒤로 점프하면 안 된다 — 워치 거리에서 이어서 센다
    func testTakeoverContinuesDistanceFromWatchValue() {
        let s = makeSession()
        s.start(healthManagedExternally: true)
        s.recordWatchDistance(500)
        XCTAssertEqual(s.distanceMeters, 500)

        s.takeOverHealthWorkout(since: now)

        XCTAssertEqual(s.distanceMeters, 500)
        s.recordWatchDistance(900)                   // 인계 뒤 늦게 오는 워치 값은 무시
        XCTAssertEqual(s.distanceMeters, 500)
    }

    @MainActor
    func testFinishSavesRunForOwner() throws {
        let container = try ModelContainer(for: Run.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let s = makeSession()
        s.start()
        now += 120
        let run = try XCTUnwrap(s.finish(ownerID: owner, weightKg: 60, context: context))
        XCTAssertEqual(s.state, .finished)
        XCTAssertEqual(run.movingSeconds, 120)
        XCTAssertEqual(run.ownerID, owner)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Run>()).count, 1)
    }

    @MainActor
    func testFinishStopsHeartRateStreamAndCalculatesHeartRate() async throws {
        let container = try ModelContainer(for: Run.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let health = HealthSpy()
        let workoutSaved = expectation(description: "HealthKit workout saved")
        health.saveExpectation = workoutSaved
        let s = RunSession(location: LocationService(), health: health, now: { self.now })
        s.start()
        health.onSample?(120)
        health.onSample?(180)

        let run = try XCTUnwrap(s.finish(ownerID: owner, weightKg: 60, context: context))

        XCTAssertTrue(health.didStopStream)
        XCTAssertEqual(run.averageHeartRate, 150)
        XCTAssertEqual(run.maxHeartRate, 180)
        await fulfillment(of: [workoutSaved], timeout: 1)
        XCTAssertEqual(health.savedSummary?.startedAt, run.startedAt)
        XCTAssertEqual(health.savedSummary?.endedAt, run.endedAt)
        XCTAssertEqual(health.savedSummary?.distanceMeters, run.distanceMeters)
        XCTAssertEqual(health.savedSummary?.calories, run.calories)
    }

    /// 세션은 앱 수명이라 같은 객체로 두 번째 러닝을 시작한다 — 지난 시간·심박이 섞이면 안 된다
    @MainActor
    func testFinishThenStartAgainStartsFresh() throws {
        let container = try ModelContainer(for: Run.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let s = makeSession()
        s.start()
        s.recordHeartRate(150)
        now += 60
        s.finish(ownerID: owner, weightKg: 60, context: context)

        s.start()
        XCTAssertEqual(s.state, .running)
        XCTAssertEqual(s.elapsedSeconds, 0)
        XCTAssertNil(s.heartRate)
        XCTAssertEqual(s.heartRateSamples, [])
        now += 10
        let second = try XCTUnwrap(s.finish(ownerID: owner, weightKg: 60, context: context))
        XCTAssertEqual(second.movingSeconds, 10)
        XCTAssertNil(second.averageHeartRate)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Run>()).count, 2)
    }

    /// 종료 연타·워치 end 중복으로 같은 러닝이 두 번 저장되지 않는다
    @MainActor
    func testFinishTwiceSavesOnce() throws {
        let container = try ModelContainer(for: Run.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let s = makeSession()
        XCTAssertNil(s.finish(ownerID: owner, weightKg: 60, context: context))   // 시작 전
        s.start()
        XCTAssertNotNil(s.finish(ownerID: owner, weightKg: 60, context: context))
        XCTAssertNil(s.finish(ownerID: owner, weightKg: 60, context: context))   // 이미 끝남
        XCTAssertEqual(try context.fetch(FetchDescriptor<Run>()).count, 1)
    }

    /// 벽시계가 뒤로 가도(자동 시간 보정) 경과 시간이 음수가 되지 않는다
    func testClockGoingBackwardsNeverGoesNegative() {
        let s = makeSession()
        s.start()
        now -= 5
        XCTAssertEqual(s.elapsedSeconds, 0)
        s.pause()                                   // 음수 구간이 accumulated에 쌓이지 않는다
        now += 30
        s.resume()
        now += 10
        XCTAssertEqual(s.elapsedSeconds, 10)
    }
}
