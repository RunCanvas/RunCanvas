import XCTest
@testable import RunCanvas

final class ProfileTests: XCTestCase {
    func testDecodesSnakeCaseColumnsAndIgnoresExtras() throws {
        let json = #"{"id":"11111111-1111-1111-1111-111111111111","nickname":"다은","weight_kg":52.5,"avatar_url":null,"created_at":"2026-08-25T00:00:00Z"}"#
        let profile = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.nickname, "다은")
        XCTAssertEqual(profile.weightKg, 52.5)
        XCTAssertNil(profile.avatarURL)
    }

    func testEncodesSnakeCaseForUpsert() throws {
        let profile = Profile(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, nickname: "동하", weightKg: 70, avatarURL: nil)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as! [String: Any]
        XCTAssertEqual(object["weight_kg"] as? Double, 70)
        XCTAssertEqual(object["id"] as? String, "11111111-1111-1111-1111-111111111111")
        // nil은 키 자체가 빠진다 → PostgREST upsert가 기존 avatar_url을 덮어쓰지 않음 (의도된 동작)
        XCTAssertFalse(object.keys.contains("avatar_url"))
    }

    func testCacheLocallyWritesAppStorageKeys() {
        let profile = Profile(id: UUID(), nickname: "테스트", weightKg: 61.5, avatarURL: "https://x/a.jpg")
        profile.cacheLocally()
        let d = UserDefaults.standard
        XCTAssertEqual(d.string(forKey: "userNickname"), "테스트")
        XCTAssertEqual(d.double(forKey: "userWeight"), 61.5)
        XCTAssertEqual(d.string(forKey: "avatarURL"), "https://x/a.jpg")
    }
}
