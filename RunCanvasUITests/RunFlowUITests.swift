import XCTest
import CoreLocation

/// 러닝 시작 → GPS 이동 → 종료 → 결과 → 홈 최근 기록. 로그인은 -uiTestSkipLogin으로 건너뛴다.
final class RunFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testRecordARunEndToEnd() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSkipLogin", "-uiTestReset", "-uiTestSkipHealth"]
        app.launch()

        // 홈 → 러닝 시작
        let start = app.buttons["러닝 시작"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), "홈에 러닝 시작 버튼이 없음")

        // 시작 전에 시뮬레이터 위치를 서울숲으로 (기본값 쿠퍼티노 → 첫 점 튐 방지)
        let base = (lat: 37.5445, lon: 127.0374)
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: base.lat, longitude: base.lon))
        start.tap()

        // 위치 권한 알럿 (영문/한글 시뮬레이터 모두)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Allow While' OR label CONTAINS '앱을 사용하는 동안'")).firstMatch
        if allow.waitForExistence(timeout: 5) { allow.tap() }

        // 러닝 중 화면
        XCTAssertTrue(app.staticTexts["거리"].waitForExistence(timeout: 5))

        // 시뮬레이터에 위치 권한이 "거부"로 남아 있으면 권한 알럿이 아예 안 뜨고 러닝도 시작되지 않는다.
        // 테스트가 되돌릴 수 없는 상태라, 원인을 바로 알려 주고 끝낸다.
        if app.alerts["위치 권한이 필요해요"].waitForExistence(timeout: 2) {
            XCTFail("시뮬레이터 위치 권한이 거부돼 있습니다. scripts/uitest.sh 로 실행하거나 "
                    + "`xcrun simctl privacy <UDID> grant location name.dongharyu.RunCanvas` 를 먼저 실행하세요.")
            return
        }

        // 약 320m 이동: 1초마다 7.8m (러닝으로 가능한 속도 — LocationService.maxSpeed 12m/s 아래)
        for i in 1..<42 {
            let loc = CLLocation(latitude: base.lat + Double(i) * 0.00007, longitude: base.lon)
            XCUIDevice.shared.location = XCUILocation(location: loc)
            Thread.sleep(forTimeInterval: 1.0)
        }

        Thread.sleep(forTimeInterval: 1.5)   // 마지막 위치가 앱에 반영될 시간

        // 종료 → 결과
        let finish = app.buttons["러닝 종료"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        XCTAssertTrue(app.staticTexts["러닝 완료"].waitForExistence(timeout: 5), "결과 화면이 안 뜸")

        // 첫 러닝 뱃지 토스트 (3초 뒤 사라지므로 결과 화면 직후에 확인)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '새 뱃지'")).firstMatch.waitForExistence(timeout: 3), "새 뱃지 토스트가 안 뜸")

        XCTAssertTrue(app.staticTexts["km"].exists)
        attachScreenshot(app, name: "run_result")

        // 거리 값이 0이 아닌지 (결과 화면의 큰 숫자)
        let distanceTexts = app.staticTexts.matching(NSPredicate(format: "label MATCHES '\\\\d+\\\\.\\\\d{2}'"))
        XCTAssertGreaterThan(distanceTexts.count, 0)
        let distance = Double(distanceTexts.firstMatch.label) ?? 0
        XCTAssertGreaterThan(distance, 0.25, "GPS 이동이 거리로 반영되지 않음: \(distance)km")   // 기대 0.32, 마지막 점 몇 개는 타이밍상 빠질 수 있음

        // 홈으로 → 최근 러닝
        app.buttons["홈으로"].tap()
        XCTAssertTrue(app.staticTexts["최근 러닝"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' km'")).firstMatch.exists)
        attachScreenshot(app, name: "home_after_run")

        // 최근 러닝 → 상세 (지도)
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS ' km'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["러닝 상세"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2)   // 지도 타일 로딩
        attachScreenshot(app, name: "run_detail")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
