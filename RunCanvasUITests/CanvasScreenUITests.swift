import XCTest

final class CanvasScreenUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testPresetToEditorAndExport() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSkipLogin", "-uiTestReset", "-uiTestSeedRun"]
        app.launch()

        let canvasTab = app.tabBars.buttons["런꾸"].exists ? app.tabBars.buttons["런꾸"] : app.buttons["런꾸"]
        XCTAssertTrue(canvasTab.waitForExistence(timeout: 10))
        canvasTab.tap()

        XCTAssertTrue(app.navigationBars["런꾸 1/4"].waitForExistence(timeout: 5))
        app.buttons["미드나잇"].tap()

        XCTAssertTrue(app.navigationBars["런꾸 2/4"].waitForExistence(timeout: 5))
        let run = app.staticTexts["1.25 km"]
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        run.tap()

        XCTAssertTrue(app.navigationBars["런꾸 3/4"].waitForExistence(timeout: 5))
        let distanceSticker = app.staticTexts["1.25"]
        XCTAssertTrue(distanceSticker.waitForExistence(timeout: 5))
        distanceSticker.tap()
        XCTAssertTrue(app.descendants(matching: .any)["크기 조절"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["색상"].exists)

        app.buttons["텍스트"].tap()
        let textField = app.textFields["문구를 입력하세요"]
        XCTAssertTrue(textField.waitForExistence(timeout: 3))
        textField.typeText("오늘도 달렸다")
        app.buttons["추가"].tap()

        let customText = app.staticTexts["오늘도 달렸다"]
        XCTAssertTrue(customText.waitForExistence(timeout: 3))
        customText.tap()
        XCTAssertTrue(app.buttons["텍스트 수정"].waitForExistence(timeout: 3))
        attach(app, "canvas_editor")
        app.buttons["완료"].tap()

        XCTAssertTrue(app.navigationBars["런꾸 4/4"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["사진 앱에 저장"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["저장하지 않고 꾸미기 종료"].waitForExistence(timeout: 5))
        attach(app, "canvas_export")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
