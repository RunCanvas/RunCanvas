import XCTest

/// 런꾸는 한 화면이다 — 기록 고르기 시트 → 캔버스에서 바로 편집 → 저장 시트
final class CanvasScreenUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testStudioEditsAndExportsInOneScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSkipLogin", "-uiTestReset", "-uiTestSeedRun"]
        app.launch()

        openTab("런꾸", in: app)

        // 탭은 앱 톤 그대로인 갤러리 — 편집기는 여기서 전체 화면으로 덮어 연다
        // PrimaryButton은 아이콘+텍스트라 label 이 정확히 일치하지 않을 수 있다
        let create = app.buttons.matching(NSPredicate(format: "label CONTAINS '새로 꾸미기'")).firstMatch
        // 전체 스위트로 돌릴 때 갤러리 첫 렌더가 5초를 넘겨 한 번 흔들렸다 — 탭 바 대기(15초)와 눈높이를 맞춘다
        XCTAssertTrue(create.waitForExistence(timeout: 15), "런꾸 탭에 새로 꾸미기가 없음")
        attach(app, "canvas_tab")
        create.tap()

        // 기록이 없으면 시트가 먼저 뜬다 (거리는 DemoData.samples 의 첫 항목)
        let run = app.staticTexts["5.12 km"]
        XCTAssertTrue(run.waitForExistence(timeout: 5), "기록 고르기 시트가 안 뜸")
        run.tap()

        // 같은 화면에 캔버스와 도구가 함께 있다
        let distanceSticker = app.descendants(matching: .any)["거리 스티커"]
        XCTAssertTrue(distanceSticker.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["배경"].exists)
        XCTAssertTrue(app.buttons["텍스트"].exists)
        attach(app, "studio_initial")

        // 스티커를 고르면 인스펙터(색·글꼴·삭제)가 같은 화면에 뜬다
        distanceSticker.tap()
        XCTAssertTrue(app.descendants(matching: .any)["흰색"].waitForExistence(timeout: 3), "색 팔레트가 안 뜸")
        XCTAssertTrue(app.descendants(matching: .any)["스티커 삭제"].exists)
        attach(app, "studio_selected")

        // 텍스트 추가
        app.buttons["텍스트"].tap()
        let textField = app.alerts.textFields.firstMatch   // placeholder는 label로 안 잡힌다
        XCTAssertTrue(textField.waitForExistence(timeout: 3))
        textField.typeText("오늘도 달렸다")
        app.buttons["추가"].tap()

        let customText = app.descendants(matching: .any)["오늘도 달렸다 스티커"]
        XCTAssertTrue(customText.waitForExistence(timeout: 3))

        // 배경 바꾸기도 같은 화면에서 시트로
        app.buttons["배경"].tap()
        let preset = app.buttons["선라이즈"]
        XCTAssertTrue(preset.waitForExistence(timeout: 3))
        preset.tap()
        XCTAssertTrue(distanceSticker.waitForExistence(timeout: 3), "배경 변경 후 캔버스로 돌아와야 함")
        attach(app, "studio_after_background")

        // 저장 시트
        app.buttons["저장"].tap()
        XCTAssertTrue(app.buttons["사진 앱에 저장"].waitForExistence(timeout: 10))
        attach(app, "studio_export")

        // 편집기가 탭바를 덮고 있어야 한다 (탭이 어두워지는 게 아니라 별도 전체 화면)
        app.navigationBars.buttons["닫기"].tap()          // 저장 시트 닫기

        // 저장하지 않고 나가면 한 번 물어본다
        let back = app.buttons["뒤로"]
        XCTAssertTrue(back.waitForExistence(timeout: 3), "뒤로 버튼이 없음")
        back.tap()
        let discard = app.buttons["버리고 나가기"]
        XCTAssertTrue(discard.waitForExistence(timeout: 3), "나가기 확인이 안 뜸")
        discard.tap()
        XCTAssertTrue(create.waitForExistence(timeout: 5), "나가면 런꾸 탭으로 돌아와야 함")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
