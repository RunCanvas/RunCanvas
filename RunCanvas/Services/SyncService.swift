import Foundation
import SwiftData
import Supabase

/// 폰 기록(SwiftData 원본) ↔ Supabase 사본. 실패해도 조용히 넘어가고 다음 기회(러닝 종료·앱 활성화)에 다시 시도한다.
/// - 업로드: `syncedAt == nil`인 기록·획득 뱃지
/// - 다운로드: 서버에는 있는데 이 기기에 없는 기록·뱃지 (다른 기기·재설치 복원)
enum SyncService {
    /// 업로드 → 다운로드 순서. 앱 활성화·로그인·러닝 종료 때 호출.
    @MainActor
    static func sync(context: ModelContext, ownerID: UUID) async {
        await pushPending(context: context, ownerID: ownerID)
        await pullMissing(context: context, ownerID: ownerID)
    }

    /// 서버의 내 기록 중 로컬에 없는 것을 받아 넣는다(syncedAt 표시). 뱃지 획득 날짜도 합친다(더 이른 날짜 유지).
    @MainActor
    static func pullMissing(context: ModelContext, ownerID: UUID) async {
        do {
            let remote: [RunDTO] = try await supabase.from("runs").select().eq("user_id", value: ownerID.uuidString).execute().value
            let localIDs = Set(((try? context.fetch(FetchDescriptor<Run>(predicate: #Predicate { $0.ownerID == ownerID }))) ?? []).map(\.id))
            let missing = remote.filter { !localIDs.contains($0.id) }.compactMap { $0.makeRun() }
            missing.forEach(context.insert)
            if !missing.isEmpty { try? context.save() }

            let badges: [UserBadgeDTO] = try await supabase.from("user_badges").select().eq("user_id", value: ownerID.uuidString).execute().value
            let dates = badges.reduce(into: [Badge: Date]()) { result, dto in
                if let badge = Badge(rawValue: dto.badge), let date = RunDTO.parseDate(dto.earnedAt) { result[badge] = date }
            }
            BadgeStore.merge(dates, for: ownerID)
        } catch {
            print("[Sync] 다운로드 실패:", error.localizedDescription)
        }
    }

    /// 아직 안 올라간 기록(`syncedAt == nil`)을 `runs`에 upsert하고 성공한 것만 `syncedAt`을 찍는다. 획득 뱃지는 `user_badges`에 upsert.
    @MainActor
    static func pushPending(context: ModelContext, ownerID: UUID) async {
        let descriptor = FetchDescriptor<Run>(predicate: #Predicate { $0.ownerID == ownerID && $0.syncedAt == nil })
        let pending = (try? context.fetch(descriptor)) ?? []
        if !pending.isEmpty {
            do {
                try await supabase.from("runs").upsert(pending.map(RunDTO.init)).execute()
                let now = Date.now
                pending.forEach { $0.syncedAt = now }
                try? context.save()
            } catch {
                print("[Sync] runs 업로드 실패 (\(pending.count)건):", error.localizedDescription)
            }
        }

        // ponytail: 뱃지는 최대 19행이라 매번 통째로 upsert (PK user_id+badge라 중복 없음)
        let badges = BadgeStore.earnedDates(for: ownerID).map { UserBadgeDTO(userID: ownerID, badge: $0.key, earnedAt: $0.value) }
        guard !badges.isEmpty else { return }
        do {
            try await supabase.from("user_badges").upsert(badges).execute()
        } catch {
            print("[Sync] user_badges 업로드 실패:", error.localizedDescription)
        }
    }
}
