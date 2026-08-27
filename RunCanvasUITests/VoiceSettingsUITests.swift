import XCTest

/// 설정 → 러닝 설정 → 음성 안내 화면 스크린샷
final class VoiceSettingsUITests: XCTestCase {
    func testVoiceSettingsScreenshot() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSkipLogin"]
        app.launch()

        let settingsTab = app.tabBars.buttons["설정"].exists ? app.tabBars.buttons["설정"] : app.buttons["설정"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10))
        settingsTab.tap()

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
