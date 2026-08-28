import XCTest
@testable import RunCanvas

final class StatsEngineTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        c.locale = Locale(identifier: "ko_KR")
        c.firstWeekday = 2   // 월요일 시작
        return c
    }()

    private func date(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 7))!
    }
    private func run(_ month: Int, _ day: Int, km: Double, seconds: Int) -> BadgeRun {
        BadgeRun(startedAt: date(month, day), distanceMeters: km * 1000, movingSeconds: seconds)
    }

    // 2026-08-27(목) 기준. 이번 주 = 8/24(월) ~ 8/30(일)
    private let now = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(identifier: "Asia/Seoul"), year: 2026, month: 8, day: 27, hour: 12))!
    private lazy var runs = [
        run(8, 24, km: 5, seconds: 1800),
        run(8, 25, km: 3, seconds: 1080),
        run(8, 27, km: 4, seconds: 1440),
        run(8, 23, km: 10, seconds: 3600),   // 지난주 일요일
        run(7, 10, km: 6, seconds: 2000),    // 지난달
    ]

    func testWeekSummaryExcludesLastWeek() {
        let s = StatsEngine.summary(runs: runs, period: .week, now: now, calendar: calendar)
        XCTAssertEqual(s.totalMeters, 12_000)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.totalSeconds, 4_320)
        XCTAssertEqual(s.avgPaceSecondsPerKm!, 360, accuracy: 0.001)
    }

    func testMonthAndYearSummary() {
        XCTAssertEqual(StatsEngine.summary(runs: runs, period: .month, now: now, calendar: calendar).totalMeters, 22_000)
        XCTAssertEqual(StatsEngine.summary(runs: runs, period: .year, now: now, calendar: calendar).count, 5)
    }

    func testEmptySummary() {
        let s = StatsEngine.summary(runs: [], period: .week, now: now, calendar: calendar)
        XCTAssertEqual(s, StatsEngine.Summary())
        XCTAssertNil(s.avgPaceSecondsPerKm)
    }

    func testWeekBucketsStartOnMonday() {
        let b = StatsEngine.buckets(runs: runs, period: .week, now: now, calendar: calendar)
        XCTAssertEqual(b.count, 7)
        XCTAssertEqual(b.map(\.label), ["월", "화", "수", "목", "금", "토", "일"])
        XCTAssertEqual(b.map(\.distanceMeters), [5_000, 3_000, 0, 4_000, 0, 0, 0])
    }

    func testMonthAndYearBuckets() {
        let m = StatsEngine.buckets(runs: runs, period: .month, now: now, calendar: calendar)
        XCTAssertEqual(m.count, 31)
        XCTAssertEqual(m[26].distanceMeters, 4_000)   // 27일
        XCTAssertEqual(m[22].distanceMeters, 10_000)  // 23일 (이번 달이라 포함)
        let y = StatsEngine.buckets(runs: runs, period: .year, now: now, calendar: calendar)
        XCTAssertEqual(y.count, 12)
        XCTAssertEqual(y[7].distanceMeters, 22_000)   // 8월
        XCTAssertEqual(y[6].distanceMeters, 6_000)    // 7월
    }
}
