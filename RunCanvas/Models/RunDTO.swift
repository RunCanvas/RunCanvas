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

    /// PostgREST 벌크 upsert는 배열 원소의 키 집합이 전부 같아야 한다(다르면 400 `PGRST102 All object keys must match`).
    /// 합성 Encodable은 nil 옵셔널의 키를 통째로 생략하므로, 심박 있는 기록(워치)과 없는 기록(폰)이 한 배치에 섞이면
    /// 업로드가 영구히 실패한다 → 옵셔널도 명시적으로 `null`을 쓴다.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userID, forKey: .userID)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(distanceM, forKey: .distanceM)
        try c.encode(movingS, forKey: .movingS)
        try c.encode(avgHr, forKey: .avgHr)          // nil이어도 키를 남긴다
        try c.encode(maxHr, forKey: .maxHr)
        try c.encode(calories, forKey: .calories)
        try c.encode(route, forKey: .route)
    }

    /// `route`는 서버에서 nullable이라 null인 행도 받아들인다 — 한 행 때문에 다운로드 전체가 실패하지 않게.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        userID = try c.decode(UUID.self, forKey: .userID)
        startedAt = try c.decode(String.self, forKey: .startedAt)
        endedAt = try c.decode(String.self, forKey: .endedAt)
        distanceM = try c.decode(Double.self, forKey: .distanceM)
        movingS = try c.decode(Int.self, forKey: .movingS)
        avgHr = try c.decodeIfPresent(Double.self, forKey: .avgHr)
        maxHr = try c.decodeIfPresent(Double.self, forKey: .maxHr)
        calories = try c.decode(Double.self, forKey: .calories)
        route = try c.decodeIfPresent([Point].self, forKey: .route) ?? []
    }

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// 서버 행 → 로컬 Run (이미 서버에 있으므로 syncedAt은 지금으로). 날짜가 깨져 있으면 nil.
    func makeRun() -> Run? {
        guard let started = Self.parseDate(startedAt), let ended = Self.parseDate(endedAt) else { return nil }
        let points = route.compactMap { p -> RoutePoint? in
            guard let t = Self.parseDate(p.t) else { return nil }
            return RoutePoint(latitude: p.lat, longitude: p.lon, timestamp: t)
        }
        let run = Run(id: id, ownerID: userID, startedAt: started, endedAt: ended, distanceMeters: distanceM,
                      movingSeconds: movingS, calories: calories, averageHeartRate: avgHr, maxHeartRate: maxHr, route: points)
        run.syncedAt = .now
        return run
    }

    private static let isoNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Postgres는 소수점 자릿수를 가변으로 돌려준다("…13.711+00:00", "…13.7+00:00", "…13+00:00") → 3자리로 맞춰 파싱
    static func parseDate(_ text: String) -> Date? {
        if let d = iso.date(from: text) ?? isoNoFraction.date(from: text) { return d }
        guard let range = text.range(of: #"\.\d+"#, options: .regularExpression) else { return nil }
        let digits = text[range].dropFirst()
        let fixed = text.replacingCharacters(in: range, with: "." + String((digits + "000").prefix(3)))
        return iso.date(from: fixed)
    }

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
