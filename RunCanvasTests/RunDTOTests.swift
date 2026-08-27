import XCTest
@testable import RunCanvas

final class RunDTOTests: XCTestCase {
    private func json(_ value: some Encodable) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
    }

    func testRunEncodesToRunsColumns() throws {
        let owner = UUID()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let run = Run(ownerID: owner, startedAt: start, endedAt: start.addingTimeInterval(1_800), distanceMeters: 5_000,
                      movingSeconds: 1_790, calories: 310, averageHeartRate: 150, maxHeartRate: 172,
                      route: [RoutePoint(latitude: 37.5445, longitude: 127.0374, timestamp: start)])
        let dto = RunDTO(run: run)
        let obj = try json(dto)

        XCTAssertEqual(obj["id"] as? String, run.id.uuidString)
        XCTAssertEqual(obj["user_id"] as? String, owner.uuidString)
        XCTAssertEqual(obj["started_at"] as? String, "2027-01-15T08:00:00.000Z")
        XCTAssertEqual(obj["distance_m"] as? Double, 5_000)
        XCTAssertEqual(obj["moving_s"] as? Int, 1_790)
        XCTAssertEqual(obj["avg_hr"] as? Double, 150)
        XCTAssertEqual(obj["max_hr"] as? Double, 172)
        XCTAssertEqual(obj["calories"] as? Double, 310)
        let route = obj["route"] as? [[String: Any]]
        XCTAssertEqual(route?.count, 1)
        XCTAssertEqual(route?.first?["lat"] as? Double, 37.5445)
        XCTAssertEqual(route?.first?["lon"] as? Double, 127.0374)
        XCTAssertEqual(route?.first?["t"] as? String, "2027-01-15T08:00:00.000Z")
        XCTAssertEqual(Set(obj.keys), ["id", "user_id", "started_at", "ended_at", "distance_m", "moving_s", "avg_hr", "max_hr", "calories", "route"])
    }

    func testNilHeartRateIsOmitted() throws {
        let run = Run(ownerID: UUID(), startedAt: .now, endedAt: .now, distanceMeters: 100, movingSeconds: 60, calories: 5)
        let obj = try json(RunDTO(run: run))
        XCTAssertNil(obj["avg_hr"])   // 키 생략 → 서버 컬럼은 null (nullable)
        XCTAssertNil(obj["max_hr"])
    }

    func testBadgeEncodesToUserBadgesColumns() throws {
        let owner = UUID()
        let obj = try json(UserBadgeDTO(userID: owner, badge: .fiveK, earnedAt: Date(timeIntervalSince1970: 1_800_000_000)))
        XCTAssertEqual(obj["user_id"] as? String, owner.uuidString)
        XCTAssertEqual(obj["badge"] as? String, "fiveK")
        XCTAssertEqual(obj["earned_at"] as? String, "2027-01-15T08:00:00.000Z")
    }

    /// Supabase가 실제로 돌려준 행 (2026-08-27 row_to_json) — PostgREST 포맷 그대로 디코딩되는지
    private let serverRow = """
    {"id":"47073c7a-f778-4d9c-8df2-91e733011fe8","user_id":"287104bb-a011-4e0a-85a3-232f58514703","started_at":"2026-08-27T14:07:13.711+00:00","ended_at":"2026-08-27T14:07:38.947+00:00","distance_m":0,"moving_s":14,"avg_hr":null,"max_hr":null,"calories":0,"route":[{"t": "2026-08-27T14:07:13.050Z", "lat": 35.21750327671874, "lon": 129.08922522598343}, {"t": "2026-08-27T14:07:28.737Z", "lat": 35.21750327494016, "lon": 129.08922522858703}],"created_at":"2026-08-27T14:07:41.202658+00:00"}
    """

    func testDecodesRealServerRowIntoRun() throws {
        let dto = try JSONDecoder().decode(RunDTO.self, from: Data(serverRow.utf8))
        let run = try XCTUnwrap(dto.makeRun())
        XCTAssertEqual(run.id.uuidString, "47073C7A-F778-4D9C-8DF2-91E733011FE8")
        XCTAssertEqual(run.ownerID.uuidString, "287104BB-A011-4E0A-85A3-232F58514703")
        XCTAssertEqual(run.startedAt.timeIntervalSince1970, 1_787_839_633.711, accuracy: 0.001)
        XCTAssertEqual(run.movingSeconds, 14)
        XCTAssertNil(run.averageHeartRate)
        XCTAssertEqual(run.route.count, 2)
        XCTAssertEqual(run.route[0].latitude, 35.21750327671874)
        XCTAssertNotNil(run.syncedAt)   // 서버에서 온 건 다시 올리지 않음
    }

    func testRoundTripKeepsFields() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000.25)
        let original = Run(ownerID: UUID(), startedAt: start, endedAt: start.addingTimeInterval(600), distanceMeters: 1_234.5,
                           movingSeconds: 590, calories: 80, averageHeartRate: 140, maxHeartRate: 160,
                           route: [RoutePoint(latitude: 37.5, longitude: 127.0, timestamp: start)])
        let data = try JSONEncoder().encode(RunDTO(run: original))
        let restored = try XCTUnwrap(try JSONDecoder().decode(RunDTO.self, from: data).makeRun())
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.ownerID, original.ownerID)
        XCTAssertEqual(restored.startedAt.timeIntervalSince1970, start.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(restored.distanceMeters, 1_234.5)
        XCTAssertEqual(restored.maxHeartRate, 160)
        XCTAssertEqual(restored.route.first?.longitude, 127.0)
    }

    func testParsesVariableFractionDates() {
        let expected = 1_787_839_633.0
        XCTAssertEqual(RunDTO.parseDate("2026-08-27T14:07:13.711+00:00")!.timeIntervalSince1970, expected + 0.711, accuracy: 0.001)
        XCTAssertEqual(RunDTO.parseDate("2026-08-27T14:07:13.7+00:00")!.timeIntervalSince1970, expected + 0.7, accuracy: 0.001)
        XCTAssertEqual(RunDTO.parseDate("2026-08-27T14:07:13+00:00")!.timeIntervalSince1970, expected, accuracy: 0.001)
        XCTAssertEqual(RunDTO.parseDate("2026-08-27T14:07:13.202658Z")!.timeIntervalSince1970, expected + 0.202, accuracy: 0.001)
        XCTAssertNil(RunDTO.parseDate("not a date"))
    }

    func testBadgeMergeKeepsEarliestDate() {
        let owner = UUID()
        defer { BadgeStore.reset(for: owner) }
        let d1 = Date(timeIntervalSince1970: 1_000), d2 = Date(timeIntervalSince1970: 2_000)
        BadgeStore.merge([.fiveK: d2, .tenK: d2], for: owner)
        BadgeStore.merge([.fiveK: d1], for: owner)                 // 더 이른 날짜로 갱신
        BadgeStore.merge([.tenK: Date(timeIntervalSince1970: 3_000)], for: owner)   // 늦은 날짜는 무시
        XCTAssertEqual(BadgeStore.earnedDates(for: owner), [.fiveK: d1, .tenK: d2])
    }
}
