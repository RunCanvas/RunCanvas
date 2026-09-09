import XCTest
import SwiftData
import CoreLocation
@testable import RunCanvas

final class RunSessionTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000_000)
    private let owner = UUID()
    private let location = LocationService()

    private func addDistance() {
        let points = [
            CLLocation(coordinate: .init(latitude: 37, longitude: 127), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date().addingTimeInterval(-9)),
            CLLocation(coordinate: .init(latitude: 37.0006, longitude: 127), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
        ]
        location.locationManager(CLLocationManager(), didUpdateLocations: points)
    }

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
        RunSession(location: location, now: { self.now })
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

    @MainActor
    func testFinishSavesRunForOwner() throws {
        let container = try ModelContainer(for: Run.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let s = makeSession()
        s.start()
        now += 120
        addDistance()
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
        let s = RunSession(location: location, health: health, now: { self.now })
        s.start()
        health.onSample?(120)
        health.onSample?(180)
        addDistance()

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
        addDistance()
        s.finish(ownerID: owner, weightKg: 60, context: context)

        s.start()
        XCTAssertEqual(s.state, .running)
        XCTAssertEqual(s.elapsedSeconds, 0)
        XCTAssertNil(s.heartRate)
        XCTAssertEqual(s.heartRateSamples, [])
        now += 10
        addDistance()
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
        addDistance()
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
