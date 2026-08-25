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
        try await supabase.from("profiles").upsert(profile).execute()
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
}
