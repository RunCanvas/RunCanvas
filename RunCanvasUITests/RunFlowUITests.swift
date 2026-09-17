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
                    + "`xcrun simctl privacy <UDID> grant location com.daun1997.RunCanvas` 를 먼저 실행하세요.")
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
        let confirmFinish = app.buttons["종료"]
        XCTAssertTrue(confirmFinish.waitForExistence(timeout: 3), "러닝 종료 확인창이 안 뜸")
        confirmFinish.tap()
        XCTAssertTrue(app.staticTexts["러닝 완료"].waitForExistence(timeout: 5), "결과 화면이 안 뜸")

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
        // 왜 식별자로 찾는가: "' km' 가 들어간 첫 텍스트"로 찾으면 홈 상단 카드의 주간 거리("0.32 / 20 km")가
        // 먼저 잡혀 프로필 편집으로 넘어간다. 기록 행만 가리키는 식별자를 쓴다.
        let historyDistance = app.staticTexts["runHistoryDistance"]
        XCTAssertTrue(historyDistance.waitForExistence(timeout: 5))
        attachScreenshot(app, name: "home_after_run")

        // 최근 러닝 → 상세 (지도)
        historyDistance.tap()
        XCTAssertTrue(app.navigationBars["러닝 상세"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2)   // 지도 타일 로딩
        attachScreenshot(app, name: "run_detail")

        // 첫 러닝으로 뱃지를 땄는지.
        // 결과 화면의 토스트로 확인하던 걸 옮겼다 — 3초 뒤 사라지는 애니메이션이라
        // 시뮬레이터가 바쁠 때 이미 사라진 뒤에 찾게 되어 간헐적으로 깨졌다.
        // 뱃지 화면의 획득 표시는 사라지지 않으니 같은 사실을 안정적으로 확인한다.
        app.navigationBars["러닝 상세"].buttons.firstMatch.tap()
        openTab("설정", in: app)
        let badgesRow = app.staticTexts["레벨과 뱃지"]
        XCTAssertTrue(badgesRow.waitForExistence(timeout: 5))
        badgesRow.tap()
        XCTAssertTrue(app.navigationBars["레벨과 뱃지"].waitForExistence(timeout: 5))
        let earned = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '획득'")).firstMatch
        XCTAssertTrue(earned.waitForExistence(timeout: 5), "첫 러닝을 했는데 획득한 뱃지가 없음")
        attachScreenshot(app, name: "badges_after_first_run")

        // 앱 수명 RunSession을 재사용해도 두 번째 러닝이 실제로 시작돼야 한다.
        openTab("홈", in: app)
        let secondStart = app.buttons["러닝 시작"]
        XCTAssertTrue(secondStart.waitForExistence(timeout: 5))
        secondStart.tap()
        XCTAssertTrue(app.buttons["일시정지"].waitForExistence(timeout: 5), "두 번째 러닝이 시작되지 않음")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
