import XCTest
@testable import RunCanvas

final class BadgeEngineTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func run(day: Int, km: Double, hour: Int = 7, minutes: Double? = nil) -> BadgeRun {
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
        let seconds = Int((minutes ?? km * 6) * 60)   // 기본 6분/km
        return BadgeRun(startedAt: date, distanceMeters: km * 1000, movingSeconds: seconds)
    }

    func testNoRunsNoBadges() {
        XCTAssertEqual(BadgeEngine.earned(runs: []), [])
    }

    func testFirstRunAndFiveK() {
        XCTAssertEqual(BadgeEngine.earned(runs: [run(day: 1, km: 5)], calendar: calendar), [.firstRun, .fiveK])
    }

    func testSingleRunDistanceTiers() {
        let e = { (km: Double) in BadgeEngine.earned(runs: [self.run(day: 1, km: km)], calendar: self.calendar) }
        XCTAssertTrue(e(10).contains(.tenK))
        XCTAssertFalse(e(9.9).contains(.tenK))
        XCTAssertTrue(e(15).contains(.fifteenK))
        XCTAssertTrue(e(21.1).contains(.halfMarathon))
        XCTAssertTrue(e(42.2).contains(.marathon))
        XCTAssertFalse(e(42.1).contains(.marathon))
    }

    func testStreaks() {
        let seven = (1...7).map { run(day: $0, km: 2) }
        let earned = BadgeEngine.earned(runs: seven, calendar: calendar)
        XCTAssertTrue(earned.contains(.streak3))
        XCTAssertTrue(earned.contains(.streak7))
        XCTAssertFalse(earned.contains(.streak30))

        let withGap = [1, 2, 3, 5, 6, 7, 8].map { run(day: $0, km: 2) }   // 4일 빠짐 → 최장 4일
        XCTAssertFalse(BadgeEngine.earned(runs: withGap, calendar: calendar).contains(.streak7))
        XCTAssertEqual(BadgeEngine.longestDailyStreak(withGap, calendar: calendar), 4)
    }

    func testStreakCountsOneRunPerDay() {
        let twiceADay = [run(day: 1, km: 1), run(day: 1, km: 1), run(day: 2, km: 1)]
        XCTAssertEqual(BadgeEngine.longestDailyStreak(twiceADay, calendar: calendar), 2)
    }

    func testTotalsAndCounts() {
        let runs = (1...20).map { run(day: $0, km: 5) }   // 100km, 20회
        let earned = BadgeEngine.earned(runs: runs, calendar: calendar)
        XCTAssertTrue(earned.contains(.total50km))
        XCTAssertTrue(earned.contains(.total100km))
        XCTAssertFalse(earned.contains(.total250km))
        XCTAssertTrue(earned.contains(.runs10))
        XCTAssertFalse(earned.contains(.runs50))
    }

    func testTimeOfDayBadges() {
        XCTAssertTrue(BadgeEngine.earned(runs: [run(day: 1, km: 1, hour: 5)], calendar: calendar).contains(.earlyBird))
        XCTAssertFalse(BadgeEngine.earned(runs: [run(day: 1, km: 1, hour: 6)], calendar: calendar).contains(.earlyBird))
        XCTAssertTrue(BadgeEngine.earned(runs: [run(day: 1, km: 1, hour: 21)], calendar: calendar).contains(.nightRunner))
        XCTAssertFalse(BadgeEngine.earned(runs: [run(day: 1, km: 1, hour: 20)], calendar: calendar).contains(.nightRunner))
    }

    func testProgressForLockedBadge() {
        let runs = (1...3).map { run(day: $0, km: 2) }
        XCTAssertEqual(BadgeEngine.progressValue(for: .streak7, runs: runs, calendar: calendar), 3)
        XCTAssertEqual(BadgeEngine.progressValue(for: .total50km, runs: runs, calendar: calendar), 6_000)
        XCTAssertEqual(BadgeEngine.progressValue(for: .runs10, runs: runs, calendar: calendar), 3)
    }

    func testPersonalBests() {
        let runs = [run(day: 1, km: 5, minutes: 30), run(day: 2, km: 10, minutes: 55), run(day: 3, km: 0.5, minutes: 1)]
        let pb = BadgeEngine.personalBests(runs, calendar: calendar)
        XCTAssertEqual(pb.longestRunMeters, 10_000)
        XCTAssertEqual(pb.bestPaceSecondsPerKm!, 330, accuracy: 0.01)   // 10km 55분 = 5'30" (0.5km는 제외)
        XCTAssertEqual(pb.longestStreakDays, 3)
        XCTAssertEqual(pb.totalRuns, 3)
        XCTAssertEqual(pb.totalMeters, 15_500)
    }
}

final class LevelTests: XCTestCase {
    func testTiers() {
        XCTAssertEqual(Level.forTotalDistance(0).tier, .yellow)
        XCTAssertEqual(Level.forTotalDistance(49_999).tier, .yellow)
        XCTAssertEqual(Level.forTotalDistance(50_000).tier, .orange)
        XCTAssertEqual(Level.forTotalDistance(250_000).tier, .green)
        XCTAssertEqual(Level.forTotalDistance(1_000_000).tier, .blue)
        XCTAssertEqual(Level.forTotalDistance(15_000_000).tier, .volt)
        XCTAssertNil(Level.forTotalDistance(15_000_000).nextTier)
        XCTAssertEqual(Level.forTotalDistance(50_000).number, 2)
        XCTAssertEqual(Level.forTotalDistance(50_000).title, "오렌지")
    }

    func testProgressAndRemaining() {
        let level = Level.forTotalDistance(150_000)   // 오렌지 구간 50k~250k 중간
        XCTAssertEqual(level.tier, .orange)
        XCTAssertEqual(level.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(level.remainingMeters, 100_000)
        XCTAssertEqual(Level.forTotalDistance(20_000_000).progress, 1)
        XCTAssertNil(Level.forTotalDistance(20_000_000).remainingMeters)
    }
}
