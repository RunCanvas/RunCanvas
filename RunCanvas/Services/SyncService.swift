import Foundation
import SwiftData
import Supabase
import OSLog

/// 폰 기록(SwiftData 원본) ↔ Supabase 사본. 실패해도 조용히 넘어가고 다음 기회(러닝 종료·앱 활성화)에 다시 시도한다.
/// - 업로드: `syncedAt == nil`인 기록·획득 뱃지
/// - 다운로드: 서버에는 있는데 이 기기에 없는 기록·뱃지 (다른 기기·재설치 복원)
enum SyncService {
    private static let log = Logger(subsystem: "name.dongharyu.RunCanvas", category: "sync")
    /// 한 요청에 담는 최대 건수 — 한 건이 서버에 거부돼도 나머지가 막히지 않도록 쪼갠다.
    private static let chunkSize = 20

    /// 업로드 → 다운로드 순서. 앱 활성화·로그인·러닝 종료 때 호출.
    @MainActor
    static func sync(context: ModelContext, ownerID: UUID) async {
        await pushPending(context: context, ownerID: ownerID)
        await pullMissing(context: context, ownerID: ownerID)
    }

    // MARK: - 다운로드

    /// 서버에는 있는데 이 기기에 없는 기록·뱃지를 받아 넣는다. 기록과 뱃지는 서로 실패에 영향을 주지 않는다.
    @MainActor
    static func pullMissing(context: ModelContext, ownerID: UUID) async {
        await pullRuns(context: context, ownerID: ownerID)
        await pullBadges(ownerID: ownerID)
    }

    @MainActor
    private static func pullRuns(context: ModelContext, ownerID: UUID) async {
        struct RemoteID: Decodable { let id: UUID }
        do {
            // 1) id만 먼저 — route는 1시간 러닝이 약 90KB라, 앱을 켤 때마다 전 기록을 통째로 내려받으면 안 된다.
            let remote: [RemoteID] = try await supabase.from("runs")
                .select("id")
                .eq("user_id", value: ownerID.uuidString)
                .execute().value
            let localIDs = Set(((try? context.fetch(FetchDescriptor<Run>(predicate: #Predicate { $0.ownerID == ownerID }))) ?? []).map(\.id))
            let missing = remote.map(\.id).filter { !localIDs.contains($0) }
            guard !missing.isEmpty else { return }

            // 2) 빠진 것만 본문 조회
            var inserted = 0
            for chunk in missing.chunked(by: chunkSize) {
                let rows: [RunDTO] = try await supabase.from("runs")
                    .select()
                    .in("id", values: chunk.map(\.uuidString))
                    .execute().value
                for dto in rows {
                    guard let run = dto.makeRun() else {
                        log.error("서버 기록을 복원하지 못함(날짜 형식): \(dto.id.uuidString, privacy: .public)")
                        continue
                    }
                    context.insert(run)
                    inserted += 1
                }
            }
            if inserted > 0 { try? context.save() }
        } catch {
            log.error("기록 다운로드 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private static func pullBadges(ownerID: UUID) async {
        do {
            let badges: [UserBadgeDTO] = try await supabase.from("user_badges")
                .select()
                .eq("user_id", value: ownerID.uuidString)
                .execute().value
            let dates = badges.reduce(into: [Badge: Date]()) { result, dto in
                if let badge = Badge(rawValue: dto.badge), let date = RunDTO.parseDate(dto.earnedAt) { result[badge] = date }
            }
            BadgeStore.merge(dates, for: ownerID)
        } catch {
            log.error("뱃지 다운로드 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - 업로드

    /// 아직 안 올라간 기록(`syncedAt == nil`)을 `runs`에 upsert하고 성공한 것만 `syncedAt`을 찍는다. 획득 뱃지는 `user_badges`에 upsert.
    @MainActor
    static func pushPending(context: ModelContext, ownerID: UUID) async {
        let descriptor = FetchDescriptor<Run>(predicate: #Predicate { $0.ownerID == ownerID && $0.syncedAt == nil })
        let pending = (try? context.fetch(descriptor)) ?? []
        var didUpload = false
        for chunk in pending.chunked(by: chunkSize) {
            do {
                try await supabase.from("runs").upsert(chunk.map(RunDTO.init)).execute()
                let now = Date.now
                chunk.forEach { $0.syncedAt = now }
                didUpload = true
            } catch {
                // 이 청크만 다음 기회에 다시 시도한다 (나머지 청크는 계속 진행)
                log.error("기록 업로드 실패(\(chunk.count)건): \(error.localizedDescription, privacy: .public)")
            }
        }
        if didUpload { try? context.save() }

        // 뱃지는 최대 19행이라 매번 통째로. 서버에 이미 있으면 건드리지 않는다 —
        // 로컬이 나중 날짜를 갖고 있을 수 있어(오프라인 재계산) 덮어쓰면 진짜 획득일이 뒤로 밀린다.
        let badges = BadgeStore.earnedDates(for: ownerID).map { UserBadgeDTO(userID: ownerID, badge: $0.key, earnedAt: $0.value) }
        guard !badges.isEmpty else { return }
        do {
            try await supabase.from("user_badges").upsert(badges, ignoreDuplicates: true).execute()
        } catch {
            log.error("뱃지 업로드 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - 삭제

    /// 로컬에서 지운 기록을 서버에서도 지운다 — 안 지우면 다음 다운로드가 되살린다. (RLS가 본인 행만 지우도록 보장)
    static func deleteRemote(runIDs: [UUID]) async {
        guard !runIDs.isEmpty else { return }
        for chunk in runIDs.chunked(by: chunkSize) {
            do {
                try await supabase.from("runs").delete().in("id", values: chunk.map(\.uuidString)).execute()
            } catch {
                log.error("기록 서버 삭제 실패(\(chunk.count)건): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

private extension Array {
    func chunked(by size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
