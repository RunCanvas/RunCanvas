import XCTest
import CoreLocation
import SwiftData
@testable import RunCanvas

final class VoiceCueTests: XCTestCase {
    func testProgress() {
        XCTAssertEqual(VoiceCue.progress(distanceMeters: 1000, seconds: 372), "1킬로미터. 시간 6분 12초. 페이스 6분 12초.")
        XCTAssertEqual(VoiceCue.progress(distanceMeters: 2500, seconds: 900), "2.5킬로미터. 시간 15분. 페이스 6분.")
    }

    func testDurationAndFinish() {
        XCTAssertEqual(VoiceCue.duration(3725), "1시간 2분 5초")
        XCTAssertEqual(VoiceCue.duration(0), "0초")
        XCTAssertEqual(VoiceCue.finish(distanceMeters: 3200, seconds: 1205), "러닝 종료. 총 3.2킬로미터, 20분 5초.")
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

    /// 회귀: finish가 시간 정산을 하려고 pause를 부르던 시절엔 "일시정지" → "러닝 종료"가 연달아 나왔다
    @MainActor
    func testFinishDoesNotAnnouncePause() throws {
        let container = try ModelContainer(for: Run.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let location = LocationService()
        let session = RunSession(location: location, coach: makeCoach())
        session.start()
        location.locationManager(manager, didUpdateLocations: (0..<12).map { loc(37.5445 + Double($0) * 0.0001, at: Double($0) - 9) })
        session.finish(ownerID: UUID(), weightKg: 60, context: ModelContext(container))

        XCTAssertFalse(spoken.contains("일시정지"), spoken.description)
        XCTAssertEqual(spoken.first, "러닝 시작")
        XCTAssertTrue(spoken.last?.hasPrefix("러닝 종료") == true, spoken.description)
    }

    /// 2.5.4 거절 대응: 심사자는 사무실에 앉아 있어 거리가 1m도 안 쌓인다.
    /// 시간 기준에서는 가만히 있어도 울려야, 홈 버튼을 누른 뒤 백그라운드 음성을 확인할 수 있다.
    func testTimeModeAnnouncesWhileStandingStill() {
        defaults.set(VoiceCoach.CueMode.time.rawValue, forKey: VoiceCoach.Keys.mode)
        defaults.set(60, forKey: VoiceCoach.Keys.intervalSeconds)
        var now = Date()
        let session = RunSession(coach: makeCoach(), now: { now })
        session.start()
        XCTAssertEqual(spoken, ["러닝 시작"])

        session.checkVoiceCue()                 // 아직 1분 전
        XCTAssertEqual(spoken.count, 1)

        now += 60
        session.checkVoiceCue()
        XCTAssertEqual(spoken.count, 2)
        XCTAssertTrue(spoken[1].hasPrefix("0킬로미터. 시간 1분"), spoken[1])

        session.checkVoiceCue()                 // 다음 지점 전엔 다시 말하지 않음
        XCTAssertEqual(spoken.count, 2)

        now += 60
        session.checkVoiceCue()
        XCTAssertEqual(spoken.count, 3)
    }

    /// 시간 기준을 켜 두면 거리 기준은 울리지 않아야 한다 — 둘 다 울리면 안내가 겹친다
    func testTimeModeSilencesDistanceCue() {
        defaults.set(VoiceCoach.CueMode.time.rawValue, forKey: VoiceCoach.Keys.mode)
        defaults.set(600, forKey: VoiceCoach.Keys.intervalSeconds)
        let location = LocationService()
        let session = RunSession(location: location, coach: makeCoach())
        session.start()
        location.locationManager(manager, didUpdateLocations: (0..<12).map { loc(37.5445 + Double($0) * 0.0001, at: Double($0) - 9) })
        session.checkVoiceCue()
        XCTAssertEqual(spoken, ["러닝 시작"])
    }

    func testDisabledCoachStaysSilent() {
        defaults.set(false, forKey: VoiceCoach.Keys.enabled)
        let session = RunSession(location: LocationService(), coach: makeCoach())
        session.start(); session.pause(); session.resume()
        XCTAssertEqual(spoken, [])
    }
}
