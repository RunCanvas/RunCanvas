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
    /// 걸음 수를 믿어도 되는가. 동작 권한이 거부되면 걸음이 영영 0이라, 그걸 믿고
    /// "안 움직였다"고 판단하면 진짜 러닝의 거리를 통째로 버린다.
    /// (private 이 아닌 이유: 테스트가 실기기·시뮬레이터에 상관없이 같은 값으로 돌게 하려고)
    var trustsPedometer = false

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
        trustsPedometer = CMPedometer.isDistanceAvailable()
        guard trustsPedometer else { return }
        pedometer.startUpdates(from: now()) { [weak self] data, error in
            // 동작 권한 거부 등으로 걸음이 안 들어오면, 걸음 0을 "안 움직였다"로 읽으면 안 된다
            if error != nil {
                DispatchQueue.main.async { self?.trustsPedometer = false }
                return
            }
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

    func updatePedometerDistance(_ meters: Double) {
        pedometerDistance = meters
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations where isUsable(loc) {
            currentLocation = loc
            // 제자리에서의 GPS 흔들림을 움직임으로 보지 않는다. speed 는 도플러 값이라
            // 좌표 차이보다 "움직이는가"를 훨씬 잘 안다. 음수는 "모름"이니 예전처럼 좌표로만 판단한다.
            if loc.speed >= 0, loc.speed < Self.minMovingSpeed { continue }
            if let last = lastRoutePoint {
                let d = loc.distance(from: last)
                guard d >= 5 else { continue }                                   // GPS 흔들림 무시
                let dt = loc.timestamp.timeIntervalSince(last.timestamp)
                guard dt > 0, d / dt <= Self.maxSpeed else { continue }          // 순간이동급 점프(GPS 튐) 무시
            }
            lastRoutePoint = loc
            route.append(RoutePoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, timestamp: loc.timestamp))

            // 거리는 20m 이내 점만 잇는다 — 고가 밑 30~50m짜리 점은 흔들림이 왕복으로 쌓여 거리가 부푼다
            guard loc.horizontalAccuracy <= Self.distanceAccuracy else { continue }
            if let last = lastLocation {
                // 흔들림 반경(정확도)보다 덜 움직인 건 움직인 게 아니다. 책상에 둔 폰도 정확도가
                // 20m 안으로 잡히는 순간부터 5~20m 씩 튀는 점이 그대로 거리로 쌓였다(실기기에서 확인).
                // 여기서 lastLocation 을 갱신하지 않으므로 거리를 잃지는 않는다 — 실제로 움직이면
                // 그 다음 점에서 한 번에 이어진다.
                guard loc.distance(from: last) > loc.horizontalAccuracy else { continue }
                let dt = loc.timestamp.timeIntervalSince(last.timestamp)
                let stepped = pedometerDistance - pedometerAtLastFix
                // 제자리 흔들림을 거리로 세지 않는다. 실기기 로그에서 본 책상 위 폰은
                // 정확도 5m 를 보고하면서 18초마다 13m 씩 튀었다(≈0.7m/s) — 그때 걸음은 내내 0이었다.
                // 정확도도 GPS 속도(-1, 모름)도 이걸 못 걸렀고, 걸음만 정직했다.
                //
                // 네 조건을 모두 만족할 때만 버린다. 하나라도 움직였다는 낌새가 있으면 센다 —
                // 진짜 러닝의 거리를 깎는 쪽이 흔들림을 몇 m 더 세는 쪽보다 훨씬 나쁘다.
                let positionSpeed = dt > 0 ? loc.distance(from: last) / dt : .infinity
                if trustsPedometer,                       // 걸음을 믿을 수 있고
                   stepped <= 0,                          // 걸음은 안 늘었고
                   loc.speed < Self.minMovingSpeed,       // GPS 속도도 아니라거나 모른다 하고
                   positionSpeed < Self.driftSpeed {      // 좌표로 따져도 걷는 속도가 안 된다
                    continue
                }
                // GPS가 끊겼던 구간은 직선(현)이 아니라 걸음 거리로 잰다 — 굽은 길 밑이면 직선은 짧다
                let added = dt > Self.gpsGapAfter && stepped > 0 ? stepped : loc.distance(from: last)
                gpsDistance += added
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
    /// 움직인다고 볼 최소 속도(m/s). 걷기(≈1.2)는 남기고 신호 대기·제자리만 거른다.
    static let minMovingSpeed = 0.5
    /// 걸음이 0일 때, 좌표로 따진 속도가 이 아래면 흔들림으로 본다(m/s).
    /// 가장 느린 조깅(≈2)보다 낮고 빠른 걷기(≈1.4) 언저리 — 실제로 걸으면 걸음이 잡혀 여기까지 안 온다.
    static let driftSpeed = 1.5

    /// 정확도 50m 이내. 신선도(10초)는 첫 fix에만 건다 — 시작 직후 오는 캐시된 옛 위치를 거르려는 것이고,
    /// 러닝 중엔 백그라운드에서 묶여 늦게 배달되는 fix를 버리면 그 구간 거리가 통째로 사라진다.
    /// (이상치는 12m/s 점프 필터가 잡는다)
    private func isUsable(_ loc: CLLocation) -> Bool {
        // 정확도는 멀쩡한데(5m·9m) 좌표가 깨진 fix 가 실제로 온다 — 실기기 로그에서 확인.
        // 거리 계산이 nan 이 되고, nan 비교는 전부 false 라 지금은 우연히 걸러지지만,
        // 첫 fix 가 이렇게 오면 그 좌표가 경로에 그대로 들어간다.
        guard CLLocationCoordinate2DIsValid(loc.coordinate) else { return false }
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= Self.routeAccuracy else { return false }
        return lastRoutePoint != nil || loc.timestamp.timeIntervalSince(now()) > -10
    }
}
