import XCTest

/// 공유 코스·트레이닝 화면이 기록 탭에서 실제로 열리는지. 서버 없이도 화면은 떠야 한다.
final class CourseTrainingScreenUITests: XCTestCase {
    func testCourseAndTrainingScreensOpenFromRecords() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSkipLogin", "-uiTestSeedRun"]
        app.launch()

        openTab("기록", in: app)

        openMenu(app)
        app.buttons["러닝 코스"].tap()
        XCTAssertTrue(app.navigationBars["러닝 코스"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2)          // 서버 조회가 끝나거나 실패할 때까지
        attach(app, "course_list")

        // 지도 보기 — 코스가 없으면 안내가 뜨고, 있으면 핀이 찍힌다
        app.buttons["지도로"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        attach(app, "course_map")
        XCTAssertTrue(app.buttons["목록으로"].waitForExistence(timeout: 3), "지도에서 목록으로 돌아가는 버튼이 없음")
        app.buttons["목록으로"].tap()

        // 정렬·내 코스만
        app.buttons["보기 설정"].tap()
        XCTAssertTrue(app.buttons["내 코스만"].waitForExistence(timeout: 3), "보기 설정에 내 코스만이 없음")
        app.buttons["내 코스만"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        app.navigationBars["러닝 코스"].buttons.firstMatch.tap()

        openMenu(app)
        app.buttons["트레이닝"].tap()
        XCTAssertTrue(app.navigationBars["트레이닝"].waitForExistence(timeout: 5))
        attach(app, "training_list")

        // 내장 프로그램 → 세션 목록
        let program = app.staticTexts["8주 5K 만들기"]
        XCTAssertTrue(program.waitForExistence(timeout: 3), "내장 프로그램이 안 보임")
        program.tap()
        XCTAssertTrue(app.staticTexts["1주차 1일"].waitForExistence(timeout: 3), "세션 목록이 안 보임")
        attach(app, "training_program")
    }

    private func openMenu(_ app: XCUIApplication) {
        let menu = app.buttons["더보기"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "기록 탭 더보기 메뉴가 없음")
        menu.tap()
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
