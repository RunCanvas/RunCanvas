import XCTest

/// 기록 탭 → 통계·차트 → 전체 기록 목록 스크린샷 (리셋 없이 실행해 이전 러닝 기록이 있으면 실데이터가 보임)
final class RecordsScreenUITests: XCTestCase {
    func testRecordsScreenScreenshots() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSkipLogin"]
        app.launch()

        let recordsTab = app.tabBars.buttons["기록"].exists ? app.tabBars.buttons["기록"] : app.buttons["기록"]
        XCTAssertTrue(recordsTab.waitForExistence(timeout: 10))
        recordsTab.tap()
        XCTAssertTrue(app.navigationBars["러닝 통계"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1)
        attach(app, "stats_1")

        // 기간 전환 (월)
        // 기간 전환 (월 → 년). SwiftUI 세그먼트는 tap()이 씹힐 때가 있어 좌표 탭으로.
        let picker = app.segmentedControls.firstMatch
        if picker.waitForExistence(timeout: 2) {
            for (label, name) in [("월", "stats_month"), ("년", "stats_year")] {
                let segment = picker.buttons[label]
                segment.tap()
                if !segment.isSelected { segment.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
                Thread.sleep(forTimeInterval: 0.6)
                NSLog("UITEST segment \(label) selected=\(segment.isSelected)")
                attach(app, name)
            }
            picker.buttons["주"].tap()
        }

        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.8)
        attach(app, "stats_2")

        // 전체 보기 → 목록
        let all = app.buttons["전체 보기"]
        if all.waitForExistence(timeout: 2) {
            all.tap()
            XCTAssertTrue(app.navigationBars["전체 기록"].waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 0.5)
            attach(app, "run_list")
        }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
