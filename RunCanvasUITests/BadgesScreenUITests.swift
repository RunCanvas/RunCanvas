import XCTest

/// 설정 → 레벨과 뱃지 화면 스크린샷 (리셋 없이 실행해 이전 러닝 기록이 있으면 획득 상태도 같이 보임)
final class BadgesScreenUITests: XCTestCase {
    func testBadgesScreenScreenshots() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSkipLogin"]
        app.launch()

        let settingsTab = app.tabBars.buttons["설정"].exists ? app.tabBars.buttons["설정"] : app.buttons["설정"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10))
        settingsTab.tap()

        let badgesRow = app.staticTexts["레벨과 뱃지"]
        XCTAssertTrue(badgesRow.waitForExistence(timeout: 5))
        badgesRow.tap()
        XCTAssertTrue(app.navigationBars["레벨과 뱃지"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)

        for i in 1...4 {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "badges_\(i)"
            shot.lifetime = .keepAlways
            add(shot)
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.8)
        }
    }
}
