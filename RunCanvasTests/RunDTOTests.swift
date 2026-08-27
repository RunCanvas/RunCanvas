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
}
