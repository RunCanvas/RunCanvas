import Foundation

/// Supabase `runs` 행 (docs/supabase/schema.sql) — 폰 `Run`의 서버 사본. 날짜는 ISO 8601 문자열로 보낸다.
struct RunDTO: Codable, Equatable {
    struct Point: Codable, Equatable {
        var lat: Double
        var lon: Double
        var t: String
    }

    var id: UUID
    var userID: UUID
    var startedAt: String
    var endedAt: String
    var distanceM: Double
    var movingS: Int
    var avgHr: Double?
    var maxHr: Double?
    var calories: Double
    var route: [Point]

    enum CodingKeys: String, CodingKey {
        case id, calories, route
        case userID = "user_id", startedAt = "started_at", endedAt = "ended_at"
        case distanceM = "distance_m", movingS = "moving_s", avgHr = "avg_hr", maxHr = "max_hr"
    }

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(run: Run) {
        id = run.id
        userID = run.ownerID
        startedAt = Self.iso.string(from: run.startedAt)
        endedAt = Self.iso.string(from: run.endedAt)
        distanceM = run.distanceMeters
        movingS = run.movingSeconds
        avgHr = run.averageHeartRate
        maxHr = run.maxHeartRate
        calories = run.calories
        route = run.route.map { Point(lat: $0.latitude, lon: $0.longitude, t: Self.iso.string(from: $0.timestamp)) }
    }
}

/// Supabase `user_badges` 행
struct UserBadgeDTO: Codable, Equatable {
    var userID: UUID
    var badge: String
    var earnedAt: String

    enum CodingKeys: String, CodingKey {
        case badge
        case userID = "user_id", earnedAt = "earned_at"
    }

    init(userID: UUID, badge: Badge, earnedAt: Date) {
        self.userID = userID
        self.badge = badge.rawValue
        self.earnedAt = RunDTO.iso.string(from: earnedAt)
    }
}
