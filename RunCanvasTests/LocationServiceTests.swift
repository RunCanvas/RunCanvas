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

    func testIgnoresTeleportJump() {
        let s = LocationService()
        s.locationManager(manager, didUpdateLocations: [loc(37.5445, at: -3), loc(37.6445, at: -2), loc(37.5446, at: -1)])   // 가운데 11km 점프
        XCTAssertEqual(s.route.count, 2)
        XCTAssertEqual(s.totalDistance, 11.1, accuracy: 0.5)   // 점프 제외, 다음 점은 마지막 정상 점 기준
    }
}
