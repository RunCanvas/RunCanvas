import XCTest
import SwiftData
@testable import RunCanvas

final class RunSessionTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000_000)
    private let owner = UUID()

    private final class HealthSpy: HealthServicing {
        var didStartStream = false
        var didStopStream = false
        var savedSummary: WorkoutSummary?
        var onSample: ((Double) -> Void)?
        var saveExpectation: XCTestExpectation?

        func requestAuthorization() async throws {}

        func startHeartRateStream(since startDate: Date, onSample: @escaping (Double) -> Void) {
            didStartStream = true
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

        let run = s.finish(ownerID: owner, weightKg: 60, context: context)

        XCTAssertTrue(health.didStopStream)
        XCTAssertEqual(run.averageHeartRate, 150)
        XCTAssertEqual(run.maxHeartRate, 180)
        await fulfillment(of: [workoutSaved], timeout: 1)
        XCTAssertEqual(health.savedSummary?.startedAt, run.startedAt)
        XCTAssertEqual(health.savedSummary?.endedAt, run.endedAt)
        XCTAssertEqual(health.savedSummary?.distanceMeters, run.distanceMeters)
        XCTAssertEqual(health.savedSummary?.calories, run.calories)
    }
}
