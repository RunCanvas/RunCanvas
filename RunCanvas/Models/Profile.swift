import Foundation

/// Supabase `profiles` 테이블 행. 서버가 원본, @AppStorage(userNickname·userWeight·avatarURL)는 로컬 캐시.
struct Profile: Codable, Identifiable, Equatable {
    let id: UUID
    var nickname: String
    var weightKg: Double?
    var avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id, nickname
        case weightKg = "weight_kg"
        case avatarURL = "avatar_url"
    }

    /// 기존 화면들이 읽는 @AppStorage 키에 복사한다 (오프라인에서도 닉네임·체중 사용).
    func cacheLocally() {
        let defaults = UserDefaults.standard
        defaults.set(nickname, forKey: "userNickname")
        if let weightKg { defaults.set(weightKg, forKey: "userWeight") }
        defaults.set(avatarURL ?? "", forKey: "avatarURL")
    }

    static func clearLocalCache() {
        let defaults = UserDefaults.standard
        ["userNickname", "userWeight", "avatarURL"].forEach { defaults.removeObject(forKey: $0) }
    }
}
