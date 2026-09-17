import Foundation
import CoreLocation
import CoreMotion
import Observation

/// GPS 추적: 거리 누적 + 경로 포인트. 러닝 중엔 백그라운드에서도 계속 받는다 (Info.plist UIBackgroundModes=location).
/// 터널·고가 밑에서 GPS가 끊기면 그 구간은 걸음 거리(CMPedometer)로 잰다 (NSMotionUsageDescription).
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let pedometer = CMPedometer()
    private var lastLocation: CLLocation?       // 거리 기준점 — 정확도 20m 이내 점만
    private var lastRoutePoint: CLLocation?     // 경로 기준점 — 정확도 50m 이내
    private let now: () -> Date

    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var currentLocation: CLLocation?
    private(set) var route: [RoutePoint] = []
    private var gpsDistance: Double = 0
    /// 이번 start() 이후 걸음으로 잰 누적 거리(m). 시뮬레이터·권한 거부면 0에 머물러 직선 거리로 돌아간다
    private var pedometerDistance: Double = 0
    private var pedometerAtLastFix: Double = 0

    /// GPS가 끊긴 동안(터널·고가 밑)도 화면이 얼어붙지 않게 마지막 GPS 점 이후 걸음 거리를 더해 보여준다
    var totalDistance: Double { gpsDistance + gapFill }

    private var gapFill: Double {
        guard let last = lastLocation, now().timeIntervalSince(last.timestamp) > Self.gpsGapAfter else { return 0 }
        return max(0, pedometerDistance - pedometerAtLastFix)
    }

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
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
        lastRoutePoint = nil
        manager.startUpdatingLocation()
        pedometerDistance = 0
        pedometerAtLastFix = 0
        guard CMPedometer.isDistanceAvailable() else { return }
        pedometer.startUpdates(from: now()) { [weak self] data, _ in
            guard let meters = data?.distance?.doubleValue else { return }
            DispatchQueue.main.async { self?.updatePedometerDistance(meters) }
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        pedometer.stopUpdates()
        gpsDistance += gapFill              // 터널 안에서 멈추거나 끝내도 걸음으로 잰 구간을 잃지 않게
        pedometerAtLastFix = pedometerDistance
    }

    func reset() {
        gpsDistance = 0
        route = []
        lastLocation = nil
        lastRoutePoint = nil
        pedometerDistance = 0
        pedometerAtLastFix = 0
    }

    func updatePedometerDistance(_ meters: Double) { pedometerDistance = meters }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations where isUsable(loc) {
            if let last = lastRoutePoint {
                let d = loc.distance(from: last)
                guard d >= 5 else { continue }                                   // GPS 흔들림 무시
                let dt = loc.timestamp.timeIntervalSince(last.timestamp)
                guard dt > 0, d / dt <= Self.maxSpeed else { continue }          // 순간이동급 점프(GPS 튐) 무시
            }
            lastRoutePoint = loc
            currentLocation = loc
            route.append(RoutePoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, timestamp: loc.timestamp))

            // 거리는 20m 이내 점만 잇는다 — 고가 밑 30~50m짜리 점은 흔들림이 왕복으로 쌓여 거리가 부푼다
            guard loc.horizontalAccuracy <= Self.distanceAccuracy else { continue }
            if let last = lastLocation {
                let dt = loc.timestamp.timeIntervalSince(last.timestamp)
                let stepped = pedometerDistance - pedometerAtLastFix
                // GPS가 끊겼던 구간은 직선(현)이 아니라 걸음 거리로 잰다 — 굽은 길 밑이면 직선은 짧다
                gpsDistance += dt > Self.gpsGapAfter && stepped > 0 ? stepped : loc.distance(from: last)
            }
            lastLocation = loc
            pedometerAtLastFix = pedometerDistance
        }
    }

    /// 러닝으로 불가능한 속도(m/s). 100m 세계기록 ≈ 10.4m/s, 그 위는 GPS 튐으로 본다.
    static let maxSpeed = 12.0
    /// 경로(지도)에 담는 정확도 상한. 워치 HKWorkoutRoute와 같은 값 — 고가 밑 점을 버리면 지도가 직선이 된다
    static let routeAccuracy = 50.0
    /// 거리에 잇는 정확도 상한
    static let distanceAccuracy = 20.0
    /// GPS가 이만큼 끊기면(터널·고가 밑) 그 사이는 걸음 거리로 잇는다
    static let gpsGapAfter: TimeInterval = 10

    /// 정확도 50m 이내. 신선도(10초)는 첫 fix에만 건다 — 시작 직후 오는 캐시된 옛 위치를 거르려는 것이고,
    /// 러닝 중엔 백그라운드에서 묶여 늦게 배달되는 fix를 버리면 그 구간 거리가 통째로 사라진다.
    /// (이상치는 12m/s 점프 필터가 잡는다)
    private func isUsable(_ loc: CLLocation) -> Bool {
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= Self.routeAccuracy else { return false }
        return lastRoutePoint != nil || loc.timestamp.timeIntervalSince(now()) > -10
    }
}
