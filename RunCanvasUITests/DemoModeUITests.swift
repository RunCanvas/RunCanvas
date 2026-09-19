import XCTest

/// App Store 심사자는 Apple·Google·카카오 계정이 없어 소셜 로그인만으로는 앱에 들어올 수 없다(지침 2.1).
/// 로그인 화면 워드마크 5회 탭이 유일한 우회로이고, ASC 심사 메모에도 그렇게 적는다.
/// 이 경로가 조용히 사라지면 심사에서 그대로 막히므로 테스트로 못 박아 둔다.
final class DemoModeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testWordmarkFiveTapsOpensAppWithRecords() {
        let app = XCUIApplication()
        app.launch()   // 로그인 우회 인자 없이 — 심사자가 보는 화면 그대로

        let wordmark = app.staticTexts["RunCanvas"]
        XCTAssertTrue(wordmark.waitForExistence(timeout: 20), "로그인 화면이 안 뜸")
        wordmark.tap(withNumberOfTaps: 5, numberOfTouches: 1)

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15), "5회 탭으로 데모에 못 들어감")

        // 빈 앱을 보여주면 심사자가 기능을 확인할 수 없다 — 시드가 실제로 깔렸는지까지 본다
        openTab("기록", in: app)
        XCTAssertTrue(app.staticTexts["5.12 km"].waitForExistence(timeout: 10), "데모 기록이 비어 있음")
    }
}
