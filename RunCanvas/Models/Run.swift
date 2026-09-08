import Foundation
import SwiftData

/// 러닝 기록 한 건. 폰(SwiftData)이 원본, Supabase `runs`는 종료 후 업로드 사본(Phase 7).
/// `ownerID`로 계정별 분리 — 같은 폰에서 다른 계정으로 로그인하면 그 계정 기록만 보인다.
@Model
final class Run {
    @Attribute(.unique) var id: UUID
    var ownerID: UUID
    var startedAt: Date
    var endedAt: Date
    var distanceMeters: Double
    var movingSeconds: Int          // 일시정지 제외
    var calories: Double
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var route: [RoutePoint]         // ponytail: 인라인 저장. 1시간 1Hz ≈ 90KB. 장거리 기록이 많아지면 관계 테이블로 분리
    var syncedAt: Date?
    var decoratedImageFilename: String?
    /// 건강 앱에서 가져온 기록이면 그 워크아웃의 UUID. 폰이 직접 기록한 러닝은 nil —
    /// 그쪽은 시간 겹침으로 걸러진다(HealthImport 참고). 옵셔널이라 기존 저장소는 그대로 열린다.
    var healthWorkoutID: UUID?

    init(id: UUID = UUID(), ownerID: UUID, startedAt: Date, endedAt: Date, distanceMeters: Double,
         movingSeconds: Int, calories: Double, averageHeartRate: Double? = nil,
         maxHeartRate: Double? = nil, route: [RoutePoint] = [], healthWorkoutID: UUID? = nil) {
        self.id = id
        self.ownerID = ownerID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceMeters = distanceMeters
        self.movingSeconds = movingSeconds
        self.calories = calories
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.route = route
        self.healthWorkoutID = healthWorkoutID
    }

    var distanceKm: Double { distanceMeters / 1000 }
    var paceSecondsPerKm: Double? { RunMath.paceSecondsPerKm(distanceMeters: distanceMeters, seconds: movingSeconds) }

    /// 뱃지·챌린지 엔진 입력
    var badgeRun: BadgeRun { BadgeRun(startedAt: startedAt, distanceMeters: distanceMeters, movingSeconds: movingSeconds) }
}

extension Run: Identifiable {}
