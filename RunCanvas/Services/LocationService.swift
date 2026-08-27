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
        for loc in locations {
            guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 20 else { continue }   // 정확도 나쁜 점 무시
            currentLocation = loc
            guard let last = lastLocation else {
                lastLocation = loc
                route.append(RoutePoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, timestamp: loc.timestamp))
                continue
            }
            let d = loc.distance(from: last)
            guard d >= 5 else { continue }          // GPS 흔들림 무시
            totalDistance += d
            lastLocation = loc
            route.append(RoutePoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, timestamp: loc.timestamp))
        }
    }
}
