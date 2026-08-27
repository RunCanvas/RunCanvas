import XCTest
import CoreLocation
@testable import RunCanvas

final class VoiceCueTests: XCTestCase {
    func testKoreanProgress() {
        XCTAssertEqual(VoiceCue.progress(distanceMeters: 1000, seconds: 372, language: .ko), "1킬로미터. 시간 6분 12초. 페이스 6분 12초.")
        XCTAssertEqual(VoiceCue.progress(distanceMeters: 2500, seconds: 900, language: .ko), "2.5킬로미터. 시간 15분. 페이스 6분.")
    }

    func testEnglishProgress() {
        XCTAssertEqual(VoiceCue.progress(distanceMeters: 1000, seconds: 372, language: .en), "1 kilometer. Time 6 minutes 12 seconds. Pace 6 minutes 12 seconds per kilometer.")
        XCTAssertEqual(VoiceCue.progress(distanceMeters: 2500, seconds: 900, language: .en), "2.5 kilometers. Time 15 minutes. Pace 6 minutes per kilometer.")
    }

    func testDurationAndFinish() {
        XCTAssertEqual(VoiceCue.duration(3725, .ko), "1시간 2분 5초")
        XCTAssertEqual(VoiceCue.duration(0, .ko), "0초")
        XCTAssertEqual(VoiceCue.duration(61, .en), "1 minute 1 second")
        XCTAssertEqual(VoiceCue.finish(distanceMeters: 3200, seconds: 1205, language: .ko), "러닝 종료. 총 3.2킬로미터, 20분 5초.")
    }
}

final class RunSessionVoiceTests: XCTestCase {
    private let manager = CLLocationManager()
    private var spoken: [String] = []
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "VoiceCoachTests")!
        defaults.removePersistentDomain(forName: "VoiceCoachTests")
        defaults.set(100.0, forKey: VoiceCoach.Keys.interval)   // 테스트는 100m 간격 (10초 안 좌표로는 1km를 못 만든다)
        spoken = []
    }

    private func makeCoach() -> VoiceCoach {
        let c = VoiceCoach(defaults: defaults)
        c.speaker = { [unowned self] in spoken.append($0) }
        return c
    }

    private func loc(_ lat: Double, at seconds: TimeInterval) -> CLLocation {
        CLLocation(coordinate: .init(latitude: lat, longitude: 127.0374), altitude: 0,
                   horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date(timeIntervalSinceNow: seconds))
    }

    func testAnnouncesStartAndEveryInterval() {
        let location = LocationService()
        let session = RunSession(location: location, coach: makeCoach())
        session.start()
        XCTAssertEqual(spoken, ["러닝 시작"])

        // 11.1m씩 12점(-9초 ~ +2초, 10초 캐시 필터 안) = 122m, 속도 11m/s로 점프 필터 통과
        location.locationManager(manager, didUpdateLocations: (0..<12).map { loc(37.5445 + Double($0) * 0.0001, at: Double($0) - 9) })
        session.checkVoiceCue()
        XCTAssertEqual(spoken.count, 2)
        XCTAssertTrue(spoken[1].hasPrefix("0.1킬로미터. 시간"), spoken[1])

        session.checkVoiceCue()                                    // 다음 지점(200m) 전엔 다시 말하지 않음
        XCTAssertEqual(spoken.count, 2)
        session.pause()
        XCTAssertEqual(spoken.last, "일시정지")
    }

    func testDisabledCoachStaysSilent() {
        defaults.set(false, forKey: VoiceCoach.Keys.enabled)
        let session = RunSession(location: LocationService(), coach: makeCoach())
        session.start(); session.pause(); session.resume()
        XCTAssertEqual(spoken, [])
    }

    func testEnglishCues() {
        defaults.set("en", forKey: VoiceCoach.Keys.language)
        let session = RunSession(location: LocationService(), coach: makeCoach())
        session.start()
        XCTAssertEqual(spoken, ["Run started"])
    }
}
