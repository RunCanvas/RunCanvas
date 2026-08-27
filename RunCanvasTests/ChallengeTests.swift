import XCTest
@testable import RunCanvas

final class ChallengeEngineTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        c.firstWeekday = 2   // 월요일 시작
        return c
    }()

    private func date(_ month: Int, _ day: Int, hour: Int = 7) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    private func run(_ month: Int, _ day: Int, km: Double) -> BadgeRun {
        BadgeRun(startedAt: date(month, day), distanceMeters: km * 1000, movingSeconds: Int(km * 360))
    }

    func testMonthlyDistanceCountsOnlyThisMonth() {
        let now = date(8, 27)
        let runs = [run(8, 1, km: 20), run(8, 15, km: 20), run(7, 31, km: 30)]   // 7월 기록은 제외
        let s = ChallengeEngine.status(Challenge.all.first { $0.id == "month_50km" }!, runs: runs, now: now, calendar: calendar)
        XCTAssertEqual(s.value, 40_000)
        XCTAssertFalse(s.isCompleted)
        XCTAssertEqual(s.fraction, 0.8, accuracy: 0.001)
        XCTAssertEqual(s.daysLeft, 5)   // 27·28·29·30·31 (오늘 포함) → 9/1 00:00
    }

    func testWeeklyRunCountUsesCurrentWeek() {
        let now = date(8, 27)   // 목요일 (주: 8/24 월 ~ 8/30 일)
        let runs = [run(8, 24, km: 3), run(8, 25, km: 3), run(8, 23, km: 3)]   // 23일은 지난주
        let s = ChallengeEngine.status(Challenge.all.first { $0.id == "week_3runs" }!, runs: runs, now: now, calendar: calendar)
        XCTAssertEqual(s.value, 2)
        XCTAssertFalse(s.isCompleted)
    }

    func testLongestRunChallengeCompletes() {
        let now = date(8, 27)
        let s = ChallengeEngine.status(Challenge.all.first { $0.id == "month_10k" }!, runs: [run(8, 10, km: 10.5)], now: now, calendar: calendar)
        XCTAssertTrue(s.isCompleted)
        XCTAssertEqual(s.fraction, 1)
    }

    func testPeriodKeys() {
        XCTAssertEqual(ChallengeEngine.periodKey(.month, now: date(8, 27), calendar: calendar), "2026-08")
        XCTAssertEqual(ChallengeEngine.periodKey(.week, now: date(8, 27), calendar: calendar), "2026-W35")
    }
}

final class BadgeStoreTests: XCTestCase {
    override func setUp() { BadgeStore.reset() }
    override func tearDown() { BadgeStore.reset() }

    func testRecordsEarnedDateOnceAndReturnsOnlyNew() {
        let cal = Calendar(identifier: .gregorian)
        let day1 = cal.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 7))!
        let runs = [BadgeRun(startedAt: day1, distanceMeters: 5_000, movingSeconds: 1_800)]

        let first = BadgeStore.recordNewlyEarned(from: runs, now: day1, calendar: cal)
        XCTAssertEqual(first, [.firstRun, .fiveK])
        XCTAssertEqual(BadgeStore.earnedDates[.fiveK], day1)

        let again = BadgeStore.recordNewlyEarned(from: runs, now: day1.addingTimeInterval(86_400), calendar: cal)
        XCTAssertEqual(again, [])
        XCTAssertEqual(BadgeStore.earnedDates[.fiveK], day1)   // 처음 딴 날짜 유지
    }

    func testCompletedChallengeIsRecordedPerPeriod() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let aug = cal.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 7))!
        let runs = [BadgeRun(startedAt: aug, distanceMeters: 10_500, movingSeconds: 3_600)]

        XCTAssertEqual(BadgeStore.recordCompletedChallenges(from: runs, now: aug, calendar: cal).map(\.id), ["month_10k"])
        XCTAssertEqual(BadgeStore.recordCompletedChallenges(from: runs, now: aug, calendar: cal), [])
        XCTAssertTrue(BadgeStore.completedChallenges.contains("month_10k@2026-08"))
    }
}
