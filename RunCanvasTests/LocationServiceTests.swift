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
            loc(37.5445, at: -1, accuracy: 50),        // 정확도 나쁨
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

    func testIgnoresTeleportJump() {
        let s = LocationService()
        s.locationManager(manager, didUpdateLocations: [loc(37.5445, at: -3), loc(37.6445, at: -2), loc(37.5446, at: -1)])   // 가운데 11km 점프
        XCTAssertEqual(s.route.count, 2)
        XCTAssertEqual(s.totalDistance, 11.1, accuracy: 0.5)   // 점프 제외, 다음 점은 마지막 정상 점 기준
    }
}
