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

    func testIgnoresTeleportJump() {
        let s = LocationService()
        s.locationManager(manager, didUpdateLocations: [loc(37.5445, at: -3), loc(37.6445, at: -2), loc(37.5446, at: -1)])   // 가운데 11km 점프
        XCTAssertEqual(s.route.count, 2)
        XCTAssertEqual(s.totalDistance, 11.1, accuracy: 0.5)   // 점프 제외, 다음 점은 마지막 정상 점 기준
    }
}
