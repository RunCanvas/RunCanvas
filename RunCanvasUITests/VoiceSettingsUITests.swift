import XCTest

/// 설정 → 러닝 설정 → 음성 안내 화면 스크린샷
final class VoiceSettingsUITests: XCTestCase {
    func testVoiceSettingsScreenshot() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSkipLogin"]
        app.launch()

        openTab("설정", in: app)
        XCTAssertTrue(app.navigationBars["설정"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.8)
        let settingsShot = XCTAttachment(screenshot: app.screenshot())
        settingsShot.name = "settings"
        settingsShot.lifetime = .keepAlways
        add(settingsShot)

        let row = app.staticTexts["음성 안내"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.navigationBars["음성 안내"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "voice_settings"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
