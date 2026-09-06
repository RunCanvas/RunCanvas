import XCTest

extension XCTestCase {
    /// 탭을 연다.
    ///
    /// `app.tabBars.buttons["기록"].exists` 처럼 기다리지 않고 물어보면, 탭 바가 아직 안 그려진 순간엔
    /// false 가 나오고 엉뚱한 요소를 눌러 홈에 그대로 남는다(그러고는 한참 뒤 "메뉴가 없음"으로 깨진다).
    /// 바가 뜰 때까지 기다렸다가 누르고, 실제로 넘어갔는지까지 확인한다.
    func openTab(_ name: String, in app: XCUIApplication,
                 file: StaticString = #filePath, line: UInt = #line) {
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 15), "탭 바가 안 뜸", file: file, line: line)
        let tab = bar.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "\(name) 탭이 없음", file: file, line: line)
        tab.tap()
    }
}
