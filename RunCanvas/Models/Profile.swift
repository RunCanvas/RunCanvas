import Foundation

/// Supabase `profiles` 테이블 행. 서버가 원본, @AppStorage(userNickname·userWeight·userHeight·avatarURL)는 로컬 캐시.
struct Profile: Codable, Identifiable, Equatable {
    let id: UUID
    var nickname: String
    var weightKg: Double?
    var heightCm: Double?
    var avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id, nickname
        case weightKg = "weight_kg"
        case heightCm = "height_cm"
        case avatarURL = "avatar_url"
    }

    /// 기존 화면들이 읽는 @AppStorage 키에 복사한다 (오프라인에서도 닉네임·체중·키 사용).
    func cacheLocally() {
        let defaults = UserDefaults.standard
        defaults.set(nickname, forKey: "userNickname")
        // nil 이면 지운다 — 안 지우면 이전 계정의 체중·키가 남아 다음 사용자의 칼로리가 잘못 계산된다
        if let weightKg { defaults.set(weightKg, forKey: "userWeight") } else { defaults.removeObject(forKey: "userWeight") }
        if let heightCm { defaults.set(heightCm, forKey: "userHeight") } else { defaults.removeObject(forKey: "userHeight") }
        defaults.set(avatarURL ?? "", forKey: "avatarURL")
    }

    static func clearLocalCache() {
        let defaults = UserDefaults.standard
        ["userNickname", "userWeight", "userHeight", "avatarURL"].forEach { defaults.removeObject(forKey: $0) }
    }
}
