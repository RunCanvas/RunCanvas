import XCTest
@testable import RunCanvas

final class ProfileTests: XCTestCase {
    func testDecodesSnakeCaseColumnsAndIgnoresExtras() throws {
        let json = #"{"id":"11111111-1111-1111-1111-111111111111","nickname":"다은","weight_kg":52.5,"height_cm":168.2,"avatar_url":null,"created_at":"2026-08-25T00:00:00Z"}"#
        let profile = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.nickname, "다은")
        XCTAssertEqual(profile.weightKg, 52.5)
        XCTAssertEqual(profile.heightCm, 168.2)
        XCTAssertNil(profile.avatarURL)
    }

    func testEncodesSnakeCaseForUpsert() throws {
        let profile = Profile(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, nickname: "동하", weightKg: 70, heightCm: 175, avatarURL: nil)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as! [String: Any]
        XCTAssertEqual(object["weight_kg"] as? Double, 70)
        XCTAssertEqual(object["height_cm"] as? Double, 175)
        XCTAssertEqual(object["id"] as? String, "11111111-1111-1111-1111-111111111111")
        // nil 도 실어 보낸다 → 아바타를 지우면 서버 값이 NULL 로 덮어써진다
        XCTAssertTrue(object.keys.contains("avatar_url"))
        XCTAssertTrue(object["avatar_url"] is NSNull)
    }

    func testCacheLocallyWritesAppStorageKeys() {
        let profile = Profile(id: UUID(), nickname: "테스트", weightKg: 61.5, heightCm: 170, avatarURL: "https://x/a.jpg")
        profile.cacheLocally()
        let d = UserDefaults.standard
        XCTAssertEqual(d.string(forKey: "userNickname"), "테스트")
        XCTAssertEqual(d.double(forKey: "userWeight"), 61.5)
        XCTAssertEqual(d.double(forKey: "userHeight"), 170)
        XCTAssertEqual(d.string(forKey: "avatarURL"), "https://x/a.jpg")
    }

    func testProfileEncodesNilAvatarForRemoval() throws {
        let profile = Profile(id: UUID(), nickname: "테스트", weightKg: 60, heightCm: 170, avatarURL: nil)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as! [String: Any]
        XCTAssertTrue(object.keys.contains("avatar_url"))
        XCTAssertTrue(object["avatar_url"] is NSNull)
    }

    func testMeasurementsUseCurrentKeypadDecimalSeparatorAndBounds() {
        let german = Locale(identifier: "de_DE")
        XCTAssertEqual(ProfileMeasurement.height(from: "170,5", locale: german), 170.5)
        XCTAssertEqual(ProfileMeasurement.weight(from: "70,5", locale: german), 70.5)
        XCTAssertNil(ProfileMeasurement.height(from: "301", locale: german))
        XCTAssertNil(ProfileMeasurement.weight(from: "501", locale: german))
        XCTAssertNil(ProfileMeasurement.weight(from: "inf", locale: german))
    }

    func testMeasurementFormattingMatchesParsingLocaleWithoutIntConversion() {
        let german = Locale(identifier: "de_DE")
        let text = ProfileMeasurement.format(70.5, locale: german)
        XCTAssertEqual(text, "70,5")
        XCTAssertEqual(ProfileMeasurement.weight(from: text, locale: german), 70.5)
        XCTAssertFalse(ProfileMeasurement.format(1e20, locale: german).isEmpty)
    }
}
