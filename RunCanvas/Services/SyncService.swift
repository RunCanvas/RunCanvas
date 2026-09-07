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
    /// PostgREST가 한 응답에 돌려주는 최대 행 수(Supabase 기본 max-rows). 넘으면 에러 없이 잘리므로 이 단위로 페이지를 넘긴다.
    private static let pageSize = 1000
    /// 동기화 꼬리 — 앱 활성화와 러닝 종료가 겹치면 앞 작업 뒤에 이어 붙여 한 번에 하나만 돈다.
    @MainActor private static var syncTail: Task<Void, Never>?
    @MainActor private static var syncTailID: UUID?

    /// 삭제 재시도 → 업로드 → 다운로드 순서. 앱 활성화·로그인·러닝 종료 때 호출.
    @MainActor
    static func sync(context: ModelContext, ownerID: UUID) async {
        // 왜: 두 동기화가 await마다 섞이면 같은 기록을 두 번 올리고 같은 id를 두 번 insert한다.
        // 현재 꼬리를 선행 작업으로 캡처해 직렬 체인을 만든다. 완료된 Task를 while로 다시 기다리면
        // 먼저 깨어난 후속 호출이 메인 액터를 점유해, 앞 호출이 꼬리를 비우지 못하는 루프가 될 수 있다.
        let predecessor = syncTail
        let taskID = UUID()
        let task = Task { @MainActor in
            await predecessor?.value
            await deleteRemote(runIDs: pendingDeletes(for: ownerID), ownerID: ownerID)
            await pushPending(context: context, ownerID: ownerID)
            await pullMissing(context: context, ownerID: ownerID)
        }
        syncTail = task
        syncTailID = taskID
        await task.value
        // 뒤에 붙은 작업이 있으면 그 작업이 마지막에 꼬리를 비운다.
        if syncTailID == taskID {
            syncTail = nil
            syncTailID = nil
        }
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
            //    최신순으로 페이지를 넘겨 전부 모은다 — 정렬 없이 한 번에 받으면 1000건 넘는 사용자는 어느 기록이 빠질지도 모른다.
            var remote: [UUID] = []
            var page: [RemoteID] = []
            repeat {
                page = try await supabase.from("runs")
                    .select("id")
                    .eq("user_id", value: ownerID.uuidString)
                    .order("started_at", ascending: false)
                    .range(from: remote.count, to: remote.count + pageSize - 1)
                    .execute().value
                remote += page.map(\.id)
            } while page.count == pageSize
            // 왜: 로컬 조회 실패를 빈 목록으로 삼키면 전 기록이 "빠진 것"이 돼 서버 사본으로 덮이고 런꾸 이미지 링크가 끊긴다
            guard let local = try? context.fetch(FetchDescriptor<Run>(predicate: #Predicate { $0.ownerID == ownerID })) else {
                log.error("로컬 기록 조회 실패 — 다운로드 건너뜀")
                return
            }
            let skip = Set(local.map(\.id)).union(pendingDeletes(for: ownerID))   // 서버 삭제가 아직 안 끝난 기록은 되살리지 않는다
            let missing = remote.filter { !skip.contains($0) }
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
    /// 응답은 `.minimal` — 기본값(representation)은 올린 route(청크당 ~1.8MB)를 그대로 되돌려줘 왕복이 두 배가 된다.
    @MainActor
    static func pushPending(context: ModelContext, ownerID: UUID) async {
        let descriptor = FetchDescriptor<Run>(predicate: #Predicate { $0.ownerID == ownerID && $0.syncedAt == nil })
        let pending = (try? context.fetch(descriptor)) ?? []
        var didUpload = false
        for chunk in pending.chunked(by: chunkSize) {
            do {
                let dtos = chunk.map(RunDTO.init)
                try await supabase.from("runs").upsert(dtos, returning: .minimal).execute()
                // 왜: 업로드를 기다리는 동안 목록에서 지운 기록은 인스턴스가 무효화돼 속성을 쓰면 크래시한다.
                //     지운 것은 건너뛰고, 방금 upsert가 서버에 되살렸으니 다시 지운다. (id는 무효화된 인스턴스 대신 dto에서)
                let now = Date.now
                var gone: [UUID] = []
                for (run, dto) in zip(chunk, dtos) {
                    if run.isDeleted || run.modelContext == nil {
                        gone.append(dto.id)
                    } else {
                        run.syncedAt = now
                        didUpload = true
                    }
                }
                if !gone.isEmpty { await deleteRemote(runIDs: gone, ownerID: ownerID) }
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
            try await supabase.from("user_badges").upsert(badges, returning: .minimal, ignoreDuplicates: true).execute()
        } catch {
            log.error("뱃지 업로드 실패: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - 삭제

    private static let pendingDeletesKey = "pendingRemoteDeletesV2"

    struct PendingDelete: Codable, Hashable {   // internal: 테스트가 대기 목록을 직접 확인한다
        let ownerID: UUID
        let runID: UUID
    }

    /// 로컬은 지웠지만 서버 삭제가 아직 안 끝난 기록. 앱을 껐다 켜도 이어 가고,
    /// 다른 계정의 RLS 아래에서 0건 삭제 응답을 성공으로 오인하지 않도록 ownerID와 함께 저장한다.
    @MainActor
    static var pendingDeletes: [PendingDelete] {
        get {
            guard let data = UserDefaults.standard.data(forKey: pendingDeletesKey) else { return [] }
            return (try? JSONDecoder().decode([PendingDelete].self, from: data)) ?? []
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: pendingDeletesKey)
        }
    }

    @MainActor
    static func pendingDeletes(for ownerID: UUID) -> [UUID] {
        pendingDeletes.filter { $0.ownerID == ownerID }.map(\.runID)
    }

    /// 로컬에서 지운 기록을 서버에서도 지운다 — 안 지우면 다음 다운로드가 되살린다. (RLS가 본인 행만 지우도록 보장)
    /// 왜 대기 목록: 비행기 모드·서버 오류로 실패하면 로그만 남고 끝나 다음 `sync()`가 그 기록을 그대로 되살렸다.
    /// 실패한 id는 목록에 남아 다음 `sync()`가 다시 지우고, 그동안 다운로드에서도 제외된다.
    @MainActor
    static func deleteRemote(runIDs: [UUID], ownerID: UUID) async {
        guard !runIDs.isEmpty else { return }
        var queued = Set(pendingDeletes)
        runIDs.forEach { queued.insert(PendingDelete(ownerID: ownerID, runID: $0)) }
        pendingDeletes = Array(queued)   // 요청 전에 먼저 적어 둔다 — 도중에 앱이 죽어도 남게
        for chunk in runIDs.chunked(by: chunkSize) {
            do {
                try await supabase.from("runs")
                    .delete(returning: .minimal)
                    .eq("user_id", value: ownerID.uuidString)
                    .in("id", values: chunk.map(\.uuidString))
                    .execute()
                pendingDeletes.removeAll { $0.ownerID == ownerID && chunk.contains($0.runID) }
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
