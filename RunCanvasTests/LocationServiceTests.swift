import XCTest
import CoreLocation
@testable import RunCanvas

final class LocationServiceTests: XCTestCase {
    private let manager = CLLocationManager()

    /// 위도 0.0001° ≈ 11.1m
    private func loc(_ lat: Double, lon: Double = 127.0374, at seconds: TimeInterval, accuracy: Double = 5) -> CLLocation {
        CLLocation(coordinate: .init(latitude: lat, longitude: lon), altitude: 0,
                   horizontalAccuracy: accuracy, verticalAccuracy: 5, timestamp: Date(timeIntervalSinceNow: seconds))
    }

    func testAccumulatesDistanceAlongRoute() {
        let s = LocationService()
        s.locationManager(manager, didUpdateLocations: [loc(37.5445, at: -3), loc(37.5446, at: -2), loc(37.5447, at: -1)])
        XCTAssertEqual(s.route.count, 3)
        XCTAssertEqual(s.totalDistance, 22.2, accuracy: 0.5)
    }

    func testIgnoresStaleAndInaccurateFixes() {
        let s = LocationService()
        s.locationManager(manager, didUpdateLocations: [
            loc(37.33, lon: -122.03, at: -120),        // 시작 직후 오는 캐시된 옛 위치 (쿠퍼티노)
            loc(37.5445, at: -1, accuracy: 80),        // 정확도 나쁨 (경로에도 못 들어간다)
            loc(37.5445, at: 0),
        ])
        XCTAssertEqual(s.route.count, 1)
        XCTAssertEqual(s.route.first?.latitude, 37.5445)
        XCTAssertEqual(s.totalDistance, 0)
    }

    /// 백그라운드에서 CoreLocation이 fix를 묶어 늦게 배달해도 그 구간 거리가 사라지면 안 된다.
    /// (신선도 10초 필터는 시작 직후 캐시된 옛 위치를 거르는 용도라 첫 fix에만 걸린다)
    func testCountsStaleFixesAfterFirstFix() {
        let start = Date()
        var now = start
        let s = LocationService(now: { now })

        s.locationManager(manager, didUpdateLocations: [at(37.5445, start)])          // 첫 fix (신선)
        now = start.addingTimeInterval(60)                                            // 60초 뒤 한꺼번에 배달
        s.locationManager(manager, didUpdateLocations: [
            at(37.5446, start.addingTimeInterval(20)),
            at(37.5447, start.addingTimeInterval(40)),
        ])

        XCTAssertEqual(s.route.count, 3)
        XCTAssertEqual(s.totalDistance, 22.2, accuracy: 0.5)
    }

    /// 절대 시각으로 만드는 위치 (신선도 필터 테스트용)
    private func at(_ lat: Double, _ timestamp: Date, lon: Double = 127.0374, accuracy: Double = 5) -> CLLocation {
        CLLocation(coordinate: .init(latitude: lat, longitude: lon), altitude: 0,
                   horizontalAccuracy: accuracy, verticalAccuracy: 5, timestamp: timestamp)
    }

    /// 고가 밑 20~50m짜리 점은 지도에는 남기되(직선으로 그려지지 않게) 거리에는 안 잇는다 — 흔들림이 왕복으로 쌓인다
    func testMidAccuracyFixesJoinRouteButNotDistance() {
        let s = LocationService()
        s.locationManager(manager, didUpdateLocations: [loc(37.5445, at: -3), loc(37.5446, at: -2, accuracy: 40), loc(37.5447, at: -1)])
        XCTAssertEqual(s.route.count, 3)
        XCTAssertEqual(s.totalDistance, 22.2, accuracy: 0.5)   // 20m 이내 점끼리(1→3) 잇는다
    }

    /// 터널·고가 밑에서 GPS가 끊기면 그 구간은 직선이 아니라 걸음 거리(CMPedometer)로 잰다.
    /// 끊긴 동안에도 화면 거리가 얼어붙지 않고, 멈추거나 끝내도 그 구간을 잃지 않는다.
    func testFillsGPSGapWithPedometerDistance() {
        let start = Date()
        var now = start
        let s = LocationService(now: { now })
        s.locationManager(manager, didUpdateLocations: [at(37.5445, start)])

        now = start.addingTimeInterval(20)                                            // 고가 밑 20초
        s.locationManager(manager, didUpdateLocations: [at(37.5446, start.addingTimeInterval(10), accuracy: 80)])
        s.updatePedometerDistance(80)
        XCTAssertEqual(s.totalDistance, 80, accuracy: 0.5, "GPS가 끊긴 동안도 걸음만큼 오른다")

        now = start.addingTimeInterval(30)                                            // GPS 복귀: 직선은 33m
        s.updatePedometerDistance(110)
        s.locationManager(manager, didUpdateLocations: [at(37.5448, now)])
        XCTAssertEqual(s.totalDistance, 110, accuracy: 0.5, "끊긴 구간은 직선 대신 걸음 거리")
        XCTAssertEqual(s.route.count, 2)

        now = start.addingTimeInterval(50)                                            // 다시 끊긴 채 종료
        s.updatePedometerDistance(140)
        s.stop()
        XCTAssertEqual(s.totalDistance, 140, accuracy: 0.5, "터널 안에서 끝내도 걸음 구간을 잃지 않는다")
    }

    /// 책상에 둔 폰. 좌표는 흔들리는데 GPS 가 "안 움직인다"고 알려 준다 —
    /// 그걸 거리로 쌓으면 가만히 있어도 러닝이 늘어난다(실기기에서 확인).
    func testStationaryDriftIsNotDistance() {
        let s = LocationService()
        let drift = (0..<8).map { index in
            CLLocation(coordinate: .init(latitude: 37.5445 + Double(index % 2) * 0.0002, longitude: 127.0374),
                       altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 5,
                       course: 0, speed: 0, timestamp: Date())
        }
        s.locationManager(manager, didUpdateLocations: drift)
        XCTAssertEqual(s.totalDistance, 0)
        XCTAssertTrue(s.route.isEmpty, "제자리 흔들림은 경로에도 안 남는다")
        XCTAssertNotNil(s.currentLocation, "지도에 보여줄 현재 위치는 갱신된다")
    }

    /// 정확도는 멀쩡한데 좌표가 깨진 fix 가 실기기에서 실제로 온다(로그에서 3개 중 2개).
    /// 거리가 nan 이 되면 이후 비교가 전부 false 라 조용히 어긋난다 — 들어오기 전에 막는다.
    func testRejectsInvalidCoordinates() {
        let s = LocationService()
        let broken = CLLocation(coordinate: .init(latitude: .nan, longitude: .nan), altitude: 0,
                                horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
        s.locationManager(manager, didUpdateLocations: [broken, loc(37.5445, at: 0), broken])
        XCTAssertEqual(s.route.count, 1, "깨진 좌표는 경로에 안 들어간다")
        XCTAssertEqual(s.route.first?.latitude, 37.5445)
        XCTAssertEqual(s.totalDistance, 0)
    }

    /// 실기기 로그에서 잡은 실제 값. 책상에 둔 폰인데 GPS 는 정확도 5m 를 보고하면서
    /// 18초마다 13m 씩 튀었다. 정확도도(5m 라 좋다고 한다) 속도도(-1, 모름) 이걸 못 거른다.
    /// 그때 걸음은 내내 0이었다 — 그게 유일하게 정직한 신호였다.
    func testDeskDriftWithGoodAccuracyAndNoStepsIsNotDistance() {
        let start = Date()
        var now = start
        let s = LocationService(now: { now })
        s.trustsPedometer = true                    // 실기기에서 걸음이 살아 있는 상태
        s.locationManager(manager, didUpdateLocations: [at(37.5445, start)])
        now = start.addingTimeInterval(18)
        // 로그에서 그대로 옮긴 값: 13m / 18초 ≈ 0.74m/s, 정확도 5m, 걸음은 내내 0
        s.locationManager(manager, didUpdateLocations: [at(37.54462, now)])
        XCTAssertEqual(s.totalDistance, 0, "걸음이 0이고 걷는 속도도 안 되면 거리가 아니다")
    }

    /// 걸음을 못 믿는 상황(동작 권한 거부·시뮬레이터)에서는 예전처럼 GPS 를 쓴다 —
    /// 걸음 0을 "안 움직였다"로 읽으면 진짜 러닝의 거리를 통째로 버린다
    func testWithoutPedometerTrustGPSStillCounts() {
        let start = Date()
        var now = start
        let s = LocationService(now: { now })
        s.trustsPedometer = false
        s.locationManager(manager, didUpdateLocations: [at(37.5445, start)])
        now = start.addingTimeInterval(18)
        s.locationManager(manager, didUpdateLocations: [at(37.54462, now)])
        XCTAssertEqual(s.totalDistance, 13.3, accuracy: 1)
    }

    /// 걸음이 0이어도 좌표가 러닝 속도로 움직였으면 센다 — 만보계가 늦게 올라오는 초반에
    /// 진짜 거리를 깎으면 안 된다. 흔들림 몇 m 를 더 세는 것보다 훨씬 나쁜 일이다.
    func testNoStepsButRunningSpeedStillCounts() {
        let start = Date()
        var now = start
        let s = LocationService(now: { now })
        s.trustsPedometer = true
        s.locationManager(manager, didUpdateLocations: [at(37.5445, start)])
        now = start.addingTimeInterval(4)
        s.locationManager(manager, didUpdateLocations: [at(37.54462, now)])   // 13m / 4초 ≈ 3.3m/s
        XCTAssertEqual(s.totalDistance, 13.3, accuracy: 1)
    }

    /// 속도를 알려 주는 정상 러닝은 그대로 쌓여야 한다 — 위 필터가 실제 러닝을 깎으면 안 된다
    func testMovingWithReportedSpeedStillCounts() {
        let s = LocationService()
        let running = (0..<3).map { index in
            CLLocation(coordinate: .init(latitude: 37.5445 + Double(index) * 0.0001, longitude: 127.0374),
                       altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
                       course: 0, speed: 3, timestamp: Date(timeIntervalSinceNow: Double(index) - 3))
        }
        s.locationManager(manager, didUpdateLocations: running)
        XCTAssertEqual(s.totalDistance, 22.2, accuracy: 0.5)
    }

    /// 정확도가 나쁠 땐 그 반경 안의 움직임을 믿지 않는다. 다만 lastLocation 을 붙들고 있어
    /// 실제로 움직이면 한 번에 이어진다 — 거리를 잃지 않는다.
    func testDriftInsideAccuracyRadiusIsHeldNotLost() {
        let s = LocationService()
        // 첫 점은 신선해야 한다(10초 안) — 아니면 "시작 직후 캐시된 옛 위치"로 걸러진다.
        // 마지막 점은 시간을 벌려 둔다 — 붙여 두면 기존 순간이동(12m/s) 필터가 먼저 걸러 버린다.
        s.locationManager(manager, didUpdateLocations: [loc(37.5445, at: -9, accuracy: 15)])
        s.locationManager(manager, didUpdateLocations: [loc(37.54460, at: -8, accuracy: 15)])   // 11m — 15m 반경 안
        XCTAssertEqual(s.totalDistance, 0, "흔들림 반경 안은 거리가 아니다")

        s.locationManager(manager, didUpdateLocations: [loc(37.5449, at: 0, accuracy: 15)])     // 첫 점에서 44m
        XCTAssertEqual(s.totalDistance, 44.4, accuracy: 1, "첫 점부터 한 번에 이어진다")
    }

    func testIgnoresTeleportJump() {
        let s = LocationService()
        s.locationManager(manager, didUpdateLocations: [loc(37.5445, at: -3), loc(37.6445, at: -2), loc(37.5446, at: -1)])   // 가운데 11km 점프
        XCTAssertEqual(s.route.count, 2)
        XCTAssertEqual(s.totalDistance, 11.1, accuracy: 0.5)   // 점프 제외, 다음 점은 마지막 정상 점 기준
    }
}
