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

    /// 왜: 합성 인코더는 nil 인 칸을 아예 빼 버린다. 그러면 아바타를 지워도 서버 값이 그대로 남는다 —
    /// 업서트가 NULL 로 덮어쓰도록 옵셔널도 반드시 실어 보낸다.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(nickname, forKey: .nickname)
        try container.encode(weightKg, forKey: .weightKg)
        try container.encode(heightCm, forKey: .heightCm)
        try container.encode(avatarURL, forKey: .avatarURL)
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
