import XCTest
@testable import RunCanvas

final class MarathonScheduleTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    private func day(_ text: String) -> Date { MarathonSchedule.parseDate(text)! }
    private let now = MarathonSchedule.parseDate("2026-09-06")!

    private func event(_ name: String, _ date: String?, kind: String = "대회",
                       courses: [String] = ["10km"], region: String? = nil,
                       status: String? = nil) -> MarathonEvent {
        MarathonEvent(name: name, date: date.flatMap(MarathonSchedule.parseDate), region: region, place: "장소",
                      courses: courses, kind: kind, status: status)
    }

    // MARK: 파싱

    func testDecodesServerRow() throws {
        let json = """
        [{"name":"해리포터 런","event_date":"2026-10-03","region":"부산","place":"부산역 인근",
          "courses":["5km"],"type":"테마런","tags":[],"status":"open",
          "reg_end_date":"2026-09-30","fee_min":85000,
          "signup_url":"https://www.kormarathon.com/ko/races/harry-potter-run"}]
        """
        let events = MarathonSchedule.parseEvents(Data(json.utf8))
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.name, "해리포터 런")
        XCTAssertEqual(event.region, "부산")
        XCTAssertEqual(event.kind, "테마런")
        XCTAssertTrue(event.isAcceptingSignups)
        XCTAssertEqual(event.feeMin, 85000)
        XCTAssertNotNil(event.signupURL)
        XCTAssertEqual(event.date, day("2026-10-03"))
    }

    func testBrokenJSONGivesEmptyScheduleInsteadOfCrashing() {
        XCTAssertTrue(MarathonSchedule.parse(Data("{ 이건 JSON 이 아니다".utf8)).events.isEmpty)
        XCTAssertTrue(MarathonSchedule.parse(Data()).events.isEmpty)
        XCTAssertTrue(MarathonSchedule.parseEvents(Data("[[[".utf8)).isEmpty)
    }

    /// 배열 안 한 항목이 깨져도 나머지는 살아야 한다
    func testOneBrokenRowDoesNotDropTheRest() {
        let json = """
        [{"event_date":"2026-10-03"},
         {"name":"정상 대회","event_date":"2026-10-04","place":"서울","courses":["10km"],"type":"대회"}]
        """
        let events = MarathonSchedule.parseEvents(Data(json.utf8))
        XCTAssertEqual(events.map(\.name), ["정상 대회"])
    }

    func testMissingOrBadDateBecomesNil() {
        XCTAssertNil(MarathonSchedule.parseDate(nil))
        XCTAssertNil(MarathonSchedule.parseDate(""))
        XCTAssertNil(MarathonSchedule.parseDate("2027년 봄"))
        XCTAssertEqual(MarathonSchedule.parseDate("2026-10-03T00:00:00+09:00"), day("2026-10-03"))
    }

    // MARK: 묶기

    func testGroupsByMonthAndPutsUndatedLast() {
        let schedule = MarathonSchedule(events: [
            event("11월 대회", "2026-11-01"),
            event("날짜 미정 대회", nil),
            event("10월 대회", "2026-10-03"),
            event("10월 후반", "2026-10-25"),
        ])
        let sections = schedule.sections(now: now, calendar: calendar)
        XCTAssertEqual(sections.map(\.id), ["2026-10", "2026-11", "tbd"])
        XCTAssertEqual(sections[0].events.map(\.name), ["10월 대회", "10월 후반"])
        XCTAssertEqual(sections.last?.events.map(\.name), ["날짜 미정 대회"])
    }

    func testPastEventsAreHiddenButTodayStays() {
        let schedule = MarathonSchedule(events: [
            event("어제", "2026-09-05"),
            event("오늘", "2026-09-06"),
            event("내일", "2026-09-07"),
        ])
        let names = schedule.sections(now: now, calendar: calendar).flatMap { $0.events.map(\.name) }
        XCTAssertEqual(names, ["오늘", "내일"])
    }

    func testEmptyScheduleGivesNoSections() {
        XCTAssertTrue(MarathonSchedule().sections(now: now, calendar: calendar).isEmpty)
    }

    // MARK: 카테고리

    func testCategoryFilters() {
        let schedule = MarathonSchedule(events: [
            event("대회 하나", "2026-10-03", kind: "대회"),
            event("테마런 하나", "2026-10-04", kind: "테마런"),
            event("접수 중인 것", "2026-10-05", kind: "테마런", status: "open"),
        ])
        func names(_ category: MarathonCategory) -> [String] {
            schedule.sections(category: category, now: now, calendar: calendar).flatMap { $0.events.map(\.name) }
        }
        XCTAssertEqual(names(.all).count, 3)
        XCTAssertEqual(names(.race), ["대회 하나"])
        XCTAssertEqual(names(.theme), ["테마런 하나", "접수 중인 것"])
        XCTAssertEqual(names(.open), ["접수 중인 것"])
    }

    /// 원본 종목 문자열이 제각각이라("Half", "하프", "~5km") 넓게 매칭돼야 한다
    func testCourseFilterHandlesMessyLabels() {
        let schedule = MarathonSchedule(events: [
            event("풀 있는 대회", "2026-10-03", courses: ["10km", "Full"]),
            event("하프 대회", "2026-10-04", courses: ["하프", "5km"]),
            event("단거리", "2026-10-05", courses: ["~5km"]),
            event("십킬로", "2026-10-06", courses: ["10km"]),
        ])
        func names(_ course: MarathonCourse) -> [String] {
            schedule.sections(course: course, now: now, calendar: calendar).flatMap { $0.events.map(\.name) }
        }
        XCTAssertEqual(names(.any).count, 4)
        XCTAssertEqual(names(.full), ["풀 있는 대회"])
        XCTAssertEqual(names(.half), ["하프 대회"])
        XCTAssertEqual(names(.short), ["하프 대회", "단거리"])
        XCTAssertEqual(names(.ten), ["풀 있는 대회", "십킬로"])
    }

    func testCategoryAndCourseCombine() {
        let schedule = MarathonSchedule(events: [
            event("테마 풀", "2026-10-03", kind: "테마런", courses: ["Full"]),
            event("대회 풀", "2026-10-04", kind: "대회", courses: ["Full"]),
        ])
        let names = schedule.sections(category: .theme, course: .full, now: now, calendar: calendar)
            .flatMap { $0.events.map(\.name) }
        XCTAssertEqual(names, ["테마 풀"])
    }

    // MARK: 지역

    func testRegionFilter() {
        let schedule = MarathonSchedule(events: [
            event("서울 대회", "2026-10-03", region: "서울"),
            event("부산 대회", "2026-10-04", region: "부산"),
            event("지역 없는 대회", "2026-10-05", region: nil),
        ])
        func names(_ region: String) -> [String] {
            schedule.sections(region: region, now: now, calendar: calendar).flatMap { $0.events.map(\.name) }
        }
        XCTAssertEqual(names(MarathonRegion.all).count, 3)
        XCTAssertEqual(names("서울"), ["서울 대회"])
        XCTAssertEqual(names("부산"), ["부산 대회"])
    }

    /// 칩은 목록에 실제로 있는 지역만, 가나다순이 아니라 서울부터
    func testRegionChipsKeepFixedOrderAndSkipMissingRegions() {
        let events = [
            event("제주", "2026-10-03", region: "제주"),
            event("서울", "2026-10-04", region: "서울"),
            event("경기", "2026-10-05", region: "경기"),
            event("해외", "2026-10-06", region: "괌"),
            event("미상", "2026-10-07", region: nil),
        ]
        XCTAssertEqual(MarathonRegion.chips(for: events),
                       [MarathonRegion.all, "서울", "경기", "제주", "괌"])
        XCTAssertEqual(MarathonRegion.chips(for: []), [MarathonRegion.all])
    }

    func testCategoryCourseRegionCombine() {
        let schedule = MarathonSchedule(events: [
            event("서울 테마 풀", "2026-10-03", kind: "테마런", courses: ["Full"], region: "서울"),
            event("부산 테마 풀", "2026-10-04", kind: "테마런", courses: ["Full"], region: "부산"),
        ])
        let names = schedule.sections(category: .theme, course: .full, region: "부산", now: now, calendar: calendar)
            .flatMap { $0.events.map(\.name) }
        XCTAssertEqual(names, ["부산 테마 풀"])
    }

    // MARK: 카드 표시용 값

    func testDecodesPosterAndCountsDaysAway() throws {
        let json = """
        [{"name":"포스터 있는 대회","event_date":"2026-09-16","place":"서울","courses":["10km"],"type":"대회",
          "image_url":"https://res.cloudinary.com/x/image/upload/w_800/poster.jpg"}]
        """
        let event = try XCTUnwrap(MarathonSchedule.parseEvents(Data(json.utf8)).first)
        XCTAssertEqual(event.imageURL?.lastPathComponent, "poster.jpg")
        XCTAssertEqual(event.daysAway(now: now, calendar: calendar), 10)
        XCTAssertNil(self.event("날짜 미정", nil).daysAway(now: now, calendar: calendar))
        XCTAssertEqual(self.event("오늘", "2026-09-06").daysAway(now: now, calendar: calendar), 0)
    }

    // MARK: 번들 씨앗

    /// 서버를 못 읽을 때 쓰는 씨앗이 실제로 앱 번들에 들어갔는지
    func testBundledSeedIsShippedAndParses() {
        let schedule = MarathonSchedule.bundled(bundle: Bundle(for: type(of: self)))
        let fallback = schedule.events.isEmpty ? MarathonSchedule.bundled().events : schedule.events
        XCTAssertFalse(fallback.isEmpty, "marathons.json 이 번들에 없거나 파싱되지 않음")
        XCTAssertTrue(fallback.allSatisfy { !$0.name.isEmpty })
    }
}
