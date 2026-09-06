import XCTest

/// 마라톤 일정 — 카테고리로 걸러 보는 화면. 서버에서 받아오고 안 되면 번들 씨앗으로 물러난다.
final class MarathonScreenUITests: XCTestCase {
    func testCategoriesFilterTheList() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSkipLogin", "-uiTestSeedRun"]
        app.launch()

        openTab("기록", in: app)

        // 진입점은 기록 탭 툴바의 "더보기" 메뉴 안에 있다(마라톤·코스·트레이닝 세 개라 메뉴로 묶었다)
        let menu = app.buttons["더보기"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "기록 탭 더보기 메뉴가 없음")
        menu.tap()

        let entry = app.buttons["마라톤 일정"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "더보기 메뉴에 마라톤 일정이 없음")
        entry.tap()

        XCTAssertTrue(app.navigationBars["마라톤 일정"].waitForExistence(timeout: 5))
        // 서버 조회가 끝날 때까지
        Thread.sleep(forTimeInterval: 3)
        attach(app, "marathon_all")

        for chip in ["대회", "테마런", "접수 중"] {
            let button = app.buttons[chip]
            XCTAssertTrue(button.waitForExistence(timeout: 3), "\(chip) 카테고리 칩이 없음")
        }

        app.buttons["테마런"].tap()
        Thread.sleep(forTimeInterval: 1)
        attach(app, "marathon_theme")

        app.buttons["풀"].tap()
        Thread.sleep(forTimeInterval: 1)
        attach(app, "marathon_theme_full")

        app.buttons["전체"].firstMatch.tap()
        app.buttons["전체 거리"].tap()

        // 지역은 메뉴 알약이다 — 17개를 칩으로 깔면 가로 스크롤이 화면을 두 번 넘게 지나간다.
        // 메뉴 항목은 개수까지 붙어("서울 (12)") 나오므로 앞부분으로 찾는다
        let regionFilter = app.buttons["지역"]
        XCTAssertTrue(regionFilter.waitForExistence(timeout: 3), "지역 필터가 없음")
        regionFilter.tap()
        let seoul = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '서울'")).firstMatch
        XCTAssertTrue(seoul.waitForExistence(timeout: 3), "지역 메뉴에 서울이 없음")
        seoul.tap()
        Thread.sleep(forTimeInterval: 1)
        attach(app, "marathon_region_seoul")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
