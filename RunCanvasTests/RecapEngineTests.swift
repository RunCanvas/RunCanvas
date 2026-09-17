import XCTest
import SwiftUI
@testable import RunCanvas

final class RecapEngineTests: XCTestCase {
    /// ko_KR 기기 기본값 — 일요일 시작
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        c.locale = Locale(identifier: "ko_KR")
        c.firstWeekday = 1
        return c
    }()

    private var mondayCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        c.locale = Locale(identifier: "ko_KR")
        c.firstWeekday = 2
        return c
    }()

    /// Asia/Seoul 기준 시각
    private func date(_ y: Int, _ m: Int, _ d: Int, _ hour: Int = 7, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute, second: second))!
    }

    /// UTC 기준 시각 — 같은 순간을 서울에서 보면 +9시간
    private func utcDate(_ y: Int, _ m: Int, _ d: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
    }

    private func run(_ y: Int, _ m: Int, _ d: Int, km: Double, seconds: Int, hour: Int = 7) -> BadgeRun {
        BadgeRun(startedAt: date(y, m, d, hour), distanceMeters: km * 1000, movingSeconds: seconds)
    }

    // 2026-08-01은 토요일. 8/3·8/10은 월요일, 8/8은 토요일.
    private lazy var runs = [
        run(2026, 8, 1, km: 5, seconds: 1800),      // 토
        run(2026, 8, 3, km: 3, seconds: 1080),      // 월
        run(2026, 8, 3, km: 2, seconds: 720, hour: 20),  // 같은 날 두 번째
        run(2026, 8, 8, km: 10, seconds: 3600),     // 토
        run(2026, 7, 10, km: 6, seconds: 2000),     // 지난달
        run(2026, 9, 5, km: 4, seconds: 1500),      // 다음달
    ]

    // MARK: - 기본 집계

    func testMonthRecapAggregatesOnlyThatMonth() {
        let r = RecapEngine.recap(runs: runs, scope: .month, anchor: date(2026, 8, 15), calendar: calendar)
        XCTAssertEqual(r.title, "2026년 8월")
        XCTAssertEqual(r.totalMeters, 20_000)
        XCTAssertEqual(r.count, 4)
        XCTAssertEqual(r.totalSeconds, 7_200)
        XCTAssertEqual(r.avgPaceSecondsPerKm!, 360, accuracy: 0.001)
        XCTAssertEqual(r.longestRunMeters, 10_000)
        XCTAssertEqual(r.activeDays, 3)             // 8/1, 8/3(2회), 8/8
        XCTAssertEqual(r.busiestWeekday, "토")       // 토 2회 vs 월 2회 → 거리 15km가 이긴다
    }

    func testYearRecapCoversWholeYear() {
        let r = RecapEngine.recap(runs: runs, scope: .year, anchor: date(2026, 3, 2), calendar: calendar)
        XCTAssertEqual(r.title, "2026년")
        XCTAssertEqual(r.count, 6)
        XCTAssertEqual(r.totalMeters, 30_000)
        XCTAssertEqual(r.activeDays, 5)
    }

    // MARK: - 경계값

    func testEmptyMonthKeepsTitleAndZeroes() {
        let r = RecapEngine.recap(runs: runs, scope: .month, anchor: date(2026, 5, 10), calendar: calendar)
        XCTAssertEqual(r.title, "2026년 5월")
        XCTAssertEqual(r.count, 0)
        XCTAssertEqual(r.totalMeters, 0)
        XCTAssertNil(r.avgPaceSecondsPerKm)         // 0으로 나누지 않는다
        XCTAssertNil(r.busiestWeekday)
        XCTAssertEqual(r.activeDays, 0)
    }

    func testEmptyRunsHasNoAnchors() {
        XCTAssertEqual(RecapEngine.availableAnchors(runs: [], scope: .month, calendar: calendar), [])
    }

    /// 월말 자정 — 9/1 0시 기록이 8월에도 잡히면(DateInterval.contains) 두 달에 이중 계산된다
    func testMonthEndBoundaryIsHalfOpen() {
        let lastSecond = BadgeRun(startedAt: date(2026, 8, 31, 23, 59, 59), distanceMeters: 1_000, movingSeconds: 300)
        let midnight = BadgeRun(startedAt: date(2026, 9, 1, 0, 0, 0), distanceMeters: 2_000, movingSeconds: 600)
        let sample = [lastSecond, midnight]

        let august = RecapEngine.recap(runs: sample, scope: .month, anchor: date(2026, 8, 10), calendar: calendar)
        XCTAssertEqual(august.count, 1)
        XCTAssertEqual(august.totalMeters, 1_000)

        let september = RecapEngine.recap(runs: sample, scope: .month, anchor: date(2026, 9, 10), calendar: calendar)
        XCTAssertEqual(september.count, 1)
        XCTAssertEqual(september.totalMeters, 2_000)
    }

    /// 한국 시간 9/1 0시 30분 = UTC 8/31 15시 30분. 타임존을 무시하면 8월로 새어 들어간다.
    func testSeoulTimeZoneDecidesTheMonth() {
        let sample = [
            BadgeRun(startedAt: utcDate(2026, 8, 31, 15, 30), distanceMeters: 3_000, movingSeconds: 900),  // KST 9/1 00:30
            BadgeRun(startedAt: utcDate(2026, 8, 31, 14, 0), distanceMeters: 5_000, movingSeconds: 1_500), // KST 8/31 23:00
        ]
        XCTAssertEqual(RecapEngine.recap(runs: sample, scope: .month, anchor: date(2026, 8, 10), calendar: calendar).totalMeters, 5_000)
        XCTAssertEqual(RecapEngine.recap(runs: sample, scope: .month, anchor: date(2026, 9, 10), calendar: calendar).totalMeters, 3_000)
    }

    /// 윤년 2월 29일 — 2028-02-29는 화요일
    func testLeapDayCountsInFebruary() {
        let leap = [BadgeRun(startedAt: date(2028, 2, 29, 7), distanceMeters: 7_000, movingSeconds: 2_100)]
        let feb = RecapEngine.recap(runs: leap, scope: .month, anchor: date(2028, 2, 1), calendar: calendar)
        XCTAssertEqual(feb.title, "2028년 2월")
        XCTAssertEqual(feb.count, 1)
        XCTAssertEqual(feb.activeDays, 1)
        XCTAssertEqual(feb.busiestWeekday, "화")
        XCTAssertEqual(RecapEngine.recap(runs: leap, scope: .year, anchor: date(2028, 6, 1), calendar: calendar).count, 1)
        // 평년 2월엔 29일이 없으므로 3월로 밀리지 않는지
        XCTAssertEqual(RecapEngine.recap(runs: leap, scope: .month, anchor: date(2028, 3, 1), calendar: calendar).count, 0)
    }

    /// 월·연 집계는 주 시작 요일과 무관해야 한다 (firstWeekday 1 = 한국 기기 기본)
    func testFirstWeekdayDoesNotChangeMonthOrYear() {
        for scope in RecapEngine.Scope.allCases {
            XCTAssertEqual(
                RecapEngine.recap(runs: runs, scope: scope, anchor: date(2026, 8, 15), calendar: calendar),
                RecapEngine.recap(runs: runs, scope: scope, anchor: date(2026, 8, 15), calendar: mondayCalendar)
            )
        }
    }

    // MARK: - 요일·기간 목록

    func testBusiestWeekdayPrefersCountThenDistance() {
        // 월 2회(합 4km) vs 토 1회(10km) → 횟수가 먼저
        let sample = [
            run(2026, 8, 3, km: 2, seconds: 700),
            run(2026, 8, 10, km: 2, seconds: 700),
            run(2026, 8, 1, km: 10, seconds: 3600),
        ]
        XCTAssertEqual(RecapEngine.recap(runs: sample, scope: .month, anchor: date(2026, 8, 15), calendar: calendar).busiestWeekday, "월")
    }

    func testAvailableAnchorsAreDedupedAndNewestFirst() {
        let months = RecapEngine.availableAnchors(runs: runs, scope: .month, calendar: calendar)
        XCTAssertEqual(months.map { RecapEngine.title(for: $0, scope: .month, calendar: calendar) },
                       ["2026년 9월", "2026년 8월", "2026년 7월"])

        let years = RecapEngine.availableAnchors(runs: runs + [run(2025, 12, 1, km: 1, seconds: 300)],
                                                 scope: .year, calendar: calendar)
        XCTAssertEqual(years.map { RecapEngine.title(for: $0, scope: .year, calendar: calendar) },
                       ["2026년", "2025년"])
    }

    /// anchor는 그 기간 안의 아무 시각이어도 같은 결과
    func testAnyAnchorInsideThePeriodGivesTheSameRecap() {
        XCTAssertEqual(
            RecapEngine.recap(runs: runs, scope: .month, anchor: date(2026, 8, 1, 0), calendar: calendar),
            RecapEngine.recap(runs: runs, scope: .month, anchor: date(2026, 8, 31, 23, 59), calendar: calendar)
        )
    }

    func testZeroDistanceRunCountsButHasNoPace() {
        let zero = [BadgeRun(startedAt: date(2026, 8, 5), distanceMeters: 0, movingSeconds: 0)]
        let r = RecapEngine.recap(runs: zero, scope: .month, anchor: date(2026, 8, 5), calendar: calendar)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r.activeDays, 1)
        XCTAssertNil(r.avgPaceSecondsPerKm)
        XCTAssertEqual(r.longestRunMeters, 0)
    }
}

/// 카드가 실제로 그려지는지 — ImageRenderer가 nil을 주면 화면이 "카드 만드는 중…"에서 멈춘다.
final class RecapCardRenderTests: XCTestCase {
    @MainActor
    func testCardRendersAt1080x1350() {
        let recap = RecapEngine.Recap(title: "2026년 8월", totalMeters: 20_000, count: 4, totalSeconds: 7_200,
                                      avgPaceSecondsPerKm: 360, longestRunMeters: 10_000,
                                      activeDays: 3, busiestWeekday: "토")
        let renderer = ImageRenderer(
            content: RecapCard(recap: recap, scope: .month)
                .frame(width: CanvasExporter.size.width, height: CanvasExporter.size.height)
        )
        renderer.scale = 1
        let image = renderer.uiImage
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.size, CanvasExporter.size)
    }

    /// 기록 없는 기간도 크래시 없이 그려져야 한다
    @MainActor
    func testEmptyRecapStillRenders() {
        let renderer = ImageRenderer(
            content: RecapCard(recap: RecapEngine.Recap(title: "2026년"), scope: .year)
                .frame(width: CanvasExporter.size.width, height: CanvasExporter.size.height)
        )
        renderer.scale = 1
        XCTAssertNotNil(renderer.uiImage)
    }
}
