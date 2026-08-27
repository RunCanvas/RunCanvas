import Foundation
import CoreLocation
import Observation

/// GPS 추적: 거리 누적 + 경로 포인트. 러닝 중엔 백그라운드에서도 계속 받는다 (Info.plist UIBackgroundModes=location).
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?

    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var currentLocation: CLLocation?
    private(set) var totalDistance: Double = 0
    private(set) var route: [RoutePoint] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
    }

    func requestPermission() { manager.requestWhenInUseAuthorization() }

    func start() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        lastLocation = nil
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    func reset() {
        totalDistance = 0
        route = []
        lastLocation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations where isUsable(loc) {
            currentLocation = loc
            if let last = lastLocation {
                let d = loc.distance(from: last)
                guard d >= 5 else { continue }                                   // GPS 흔들림 무시
                let dt = loc.timestamp.timeIntervalSince(last.timestamp)
                guard dt > 0, d / dt <= Self.maxSpeed else { continue }          // 순간이동급 점프(GPS 튐) 무시
                totalDistance += d
            }
            lastLocation = loc
            route.append(RoutePoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, timestamp: loc.timestamp))
        }
    }

    /// 러닝으로 불가능한 속도(m/s). 100m 세계기록 ≈ 10.4m/s, 그 위는 GPS 튐으로 본다.
    static let maxSpeed = 12.0

    /// 정확도 20m 이내 + 10초 안에 잰 위치만 (시작 직후 오는 캐시된 옛 위치 제외)
    private func isUsable(_ loc: CLLocation) -> Bool {
        loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy <= 20 && loc.timestamp.timeIntervalSinceNow > -10
    }
}
