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

    /// ko_KR 기기 기본값 — 실제 사용자 대부분이 타는 경로
    private var sundayCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        c.locale = Locale(identifier: "ko_KR")
        c.firstWeekday = 1   // 일요일 시작
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

    // 일요일 시작(기기 기본값)이면 주 범위가 8/23~8/29로 밀려 지난주였던 8/23이 이번 주가 된다
    func testWeekStartsOnSundayForDefaultLocale() {
        let s = StatsEngine.summary(runs: runs, period: .week, now: now, calendar: sundayCalendar)
        XCTAssertEqual(s.totalMeters, 22_000)
        XCTAssertEqual(s.count, 4)

        let b = StatsEngine.buckets(runs: runs, period: .week, now: now, calendar: sundayCalendar)
        XCTAssertEqual(b.map(\.label), ["일", "월", "화", "수", "목", "금", "토"])
        XCTAssertEqual(b.map(\.distanceMeters), [10_000, 5_000, 3_000, 0, 4_000, 0, 0])
    }

    func testZeroDistanceRunCountsButHasNoPace() {
        let zero = [BadgeRun(startedAt: date(8, 27), distanceMeters: 0, movingSeconds: 0)]
        let s = StatsEngine.summary(runs: zero, period: .week, now: now, calendar: calendar)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s.totalMeters, 0)
        XCTAssertEqual(s.totalSeconds, 0)
        XCTAssertNil(s.avgPaceSecondsPerKm)   // 0으로 나누지 않는다
        XCTAssertEqual(StatsEngine.buckets(runs: zero, period: .week, now: now, calendar: calendar)[3].distanceMeters, 0)
    }

    func testLeapFebruaryHas29Buckets() {
        let feb2028 = calendar.date(from: DateComponents(year: 2028, month: 2, day: 15, hour: 7))!
        XCTAssertEqual(StatsEngine.buckets(runs: [], period: .month, now: feb2028, calendar: calendar).count, 29)
        let feb2026 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 15, hour: 7))!
        XCTAssertEqual(StatsEngine.buckets(runs: [], period: .month, now: feb2026, calendar: calendar).count, 28)
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

    func testChartAxisLabelsStayReadableAndKeepPeriodEdges() {
        let month = StatsEngine.buckets(runs: [], period: .month, now: date(9, 15), calendar: calendar)
        let monthLabels = StatsEngine.axisLabels(buckets: month, period: .month)
        XCTAssertEqual(monthLabels.count, 5)
        XCTAssertEqual(monthLabels.first, "1")
        XCTAssertEqual(monthLabels.last, "30")

        let year = StatsEngine.buckets(runs: [], period: .year, now: date(9, 15), calendar: calendar)
        let yearLabels = StatsEngine.axisLabels(buckets: year, period: .year)
        XCTAssertEqual(yearLabels.count, 6)
        XCTAssertEqual(yearLabels.first, "1월")
        XCTAssertEqual(yearLabels.last, "12월")

        let week = StatsEngine.buckets(runs: [], period: .week, now: date(9, 15), calendar: calendar)
        XCTAssertEqual(StatsEngine.axisLabels(buckets: week, period: .week).count, 7)
    }
}
