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

    /// avatars 버킷의 `<uid>/<난수>.jpg`에 올리고 공개 URL을 돌려준다.
    /// 폴더의 uid는 소문자 — 스토리지 RLS가 auth.uid()::text(소문자)와 비교한다.
    ///
    /// 왜 파일명이 난수인가: `<uid>/avatar.jpg`로 고정하면 uid만 알면 사진 주소가 계산으로 나온다.
    /// `public.courses`는 `for select using (true)`라 `owner_id`가 공개이므로, 코스를 한 번이라도
    /// 올린 사용자의 사진이 누구에게나 열린다. 난수 파일명이면 프로필을 읽을 수 있는 본인만 주소를 안다.
    /// (난수라 캐시 무효화용 `?v=` 쿼리도 필요 없어졌다 — 사진을 바꾸면 주소가 바뀐다.)
    static func uploadAvatar(userID: UUID, jpeg: Data) async throws -> String {
        let folder = userID.uuidString.lowercased()
        let bucket = supabase.storage.from("avatars")
        try await removeAll(in: folder, bucket: bucket)   // 이전 사진이 주소를 아는 사람에게 계속 열려 있지 않게
        let path = "\(folder)/\(UUID().uuidString.lowercased()).jpg"
        try await bucket.upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: true))
        return try bucket.getPublicURL(path: path).absoluteString
    }

    /// 공개 버킷의 사진은 프로필 URL만 비워서는 계속 공개되므로 원본 파일도 함께 지운다.
    static func removeAvatar(userID: UUID) async throws {
        try await removeAll(in: userID.uuidString.lowercased(), bucket: supabase.storage.from("avatars"))
    }

    /// 폴더 안 파일을 전부 지운다. 파일명이 난수라 목록을 봐야 하고,
    /// 예전 `<uid>/avatar.jpg`도 여기서 같이 정리된다.
    private static func removeAll(in folder: String, bucket: StorageFileApi) async throws {
        let paths = try await bucket.list(path: folder).map { "\(folder)/\($0.name)" }
        guard !paths.isEmpty else { return }
        _ = try await bucket.remove(paths: paths)
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
