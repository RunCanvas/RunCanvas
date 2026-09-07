import Foundation
import Supabase

enum ProfileService {
    static func fetchMine(userID: UUID) async throws -> Profile? {
        let rows: [Profile] = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    static func upsert(_ profile: Profile) async throws {
        try await supabase.from("profiles").upsert(ProfileUpsertPayload(profile)).execute()
    }

    /// avatars 버킷의 `<uid>/avatar.jpg`에 덮어쓰고 공개 URL을 돌려준다.
    /// 경로의 uid는 소문자 — 스토리지 RLS가 auth.uid()::text(소문자)와 비교한다.
    static func uploadAvatar(userID: UUID, jpeg: Data) async throws -> String {
        let path = "\(userID.uuidString.lowercased())/avatar.jpg"
        let bucket = supabase.storage.from("avatars")
        try await bucket.upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: true))
        // 캐시 무효화용 쿼리 — 같은 경로에 덮어써도 AsyncImage가 새로 받도록
        return try bucket.getPublicURL(path: path).absoluteString + "?v=\(Int(Date().timeIntervalSince1970))"
    }

    /// 공개 버킷의 사진은 프로필 URL만 비워서는 계속 공개되므로 원본 파일도 함께 지운다.
    static func removeAvatar(userID: UUID) async throws {
        let path = "\(userID.uuidString.lowercased())/avatar.jpg"
        _ = try await supabase.storage.from("avatars").remove(paths: [path])
    }
}

/// `Profile`의 합성 Encodable은 nil을 생략한다. 아바타 삭제는 서버 값을 실제 NULL로 덮어써야 한다.
struct ProfileUpsertPayload: Encodable {
    let id: UUID
    let nickname: String
    let weightKg: Double?
    let heightCm: Double?
    let avatarURL: String?

    init(_ profile: Profile) {
        id = profile.id
        nickname = profile.nickname
        weightKg = profile.weightKg
        heightCm = profile.heightCm
        avatarURL = profile.avatarURL
    }

    enum CodingKeys: String, CodingKey {
        case id, nickname
        case weightKg = "weight_kg"
        case heightCm = "height_cm"
        case avatarURL = "avatar_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(nickname, forKey: .nickname)
        try container.encodeIfPresent(weightKg, forKey: .weightKg)
        try container.encodeIfPresent(heightCm, forKey: .heightCm)
        if let avatarURL {
            try container.encode(avatarURL, forKey: .avatarURL)
        } else {
            try container.encodeNil(forKey: .avatarURL)
        }
    }
}

/// 설정·편집 화면이 같은 범위와 지역별 소수점 규칙을 쓰도록 한곳에 둔다.
enum ProfileMeasurement {
    static let maxHeightCm = 300.0
    static let maxWeightKg = 500.0

    static func height(from text: String, locale: Locale = .current) -> Double? {
        parse(text, maximum: maxHeightCm, locale: locale)
    }

    static func weight(from text: String, locale: Locale = .current) -> Double? {
        parse(text, maximum: maxWeightKg, locale: locale)
    }

    static func format(_ value: Double, locale: Locale = .current) -> String {
        let formatter = formatter(locale: locale)
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? ""
    }

    private static func parse(_ text: String, maximum: Double, locale: Locale) -> Double? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let value = formatter(locale: locale).number(from: text)?.doubleValue,
              value > 0,
              value <= maximum else { return nil }
        return value
    }

    private static func formatter(locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.isLenient = false
        formatter.usesGroupingSeparator = false
        return formatter
    }
}
