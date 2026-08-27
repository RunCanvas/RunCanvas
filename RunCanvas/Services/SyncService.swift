import Foundation
import SwiftData
import Supabase

/// 폰 기록(SwiftData 원본) → Supabase 사본 업로드. 실패해도 조용히 넘어가고 다음 기회(러닝 종료·앱 활성화)에 다시 시도한다.
/// 다운로드(다른 기기 복원)는 2.0.
enum SyncService {
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
