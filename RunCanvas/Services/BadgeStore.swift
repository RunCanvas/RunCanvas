import Foundation

/// 획득한 뱃지(날짜 포함)와 완료한 챌린지를 **계정별로** 로컬에 기억해 두고, 새 기록 뒤에 "이번에 새로 딴 것"만 골라낸다.
/// (서버 user_badges 업로드는 Phase 7 SyncService)
enum BadgeStore {
    private static func badgesKey(_ ownerID: UUID) -> String { "earnedBadgeDates.\(ownerID.uuidString)" }
    private static func challengesKey(_ ownerID: UUID) -> String { "completedChallenges.\(ownerID.uuidString)" }

    // MARK: 뱃지

    static func earnedDates(for ownerID: UUID) -> [Badge: Date] {
        let raw = UserDefaults.standard.dictionary(forKey: badgesKey(ownerID)) as? [String: Double] ?? [:]
        return raw.reduce(into: [:]) { result, pair in
            if let badge = Badge(rawValue: pair.key) { result[badge] = Date(timeIntervalSince1970: pair.value) }
        }
    }

    private static func setEarnedDates(_ dates: [Badge: Date], for ownerID: UUID) {
        let raw = dates.reduce(into: [String: Double]()) { $0[$1.key.rawValue] = $1.value.timeIntervalSince1970 }
        UserDefaults.standard.set(raw, forKey: badgesKey(ownerID))
    }

    /// 현재 기록으로 계산한 뱃지 중 아직 저장 안 된 것 → 지금 날짜로 저장하고 돌려준다 (Badge.allCases 순서)
    @discardableResult
    static func recordNewlyEarned(from runs: [BadgeRun], ownerID: UUID, now: Date = .now, calendar: Calendar = .current) -> [Badge] {
        let current = BadgeEngine.earned(runs: runs, calendar: calendar)
        var dates = earnedDates(for: ownerID)
        let fresh = Badge.allCases.filter { current.contains($0) && dates[$0] == nil }
        guard !fresh.isEmpty else { return [] }
        fresh.forEach { dates[$0] = now }
        setEarnedDates(dates, for: ownerID)
        return fresh
    }

    /// 서버에서 받은 획득 날짜를 합친다 — 이미 있으면 더 이른 날짜 유지
    static func merge(_ remote: [Badge: Date], for ownerID: UUID) {
        guard !remote.isEmpty else { return }
        var dates = earnedDates(for: ownerID)
        for (badge, date) in remote { dates[badge] = min(dates[badge] ?? date, date) }
        setEarnedDates(dates, for: ownerID)
    }

    // MARK: 챌린지

    static func completedChallenges(for ownerID: UUID) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: challengesKey(ownerID)) ?? [])
    }

    static func challengeKey(_ challenge: Challenge, now: Date = .now, calendar: Calendar = .current) -> String {
        "\(challenge.id)@\(ChallengeEngine.periodKey(challenge.period, now: now, calendar: calendar))"
    }

    /// 이번 기간에 새로 완료한 챌린지 → 저장하고 돌려준다
    @discardableResult
    static func recordCompletedChallenges(from runs: [BadgeRun], ownerID: UUID, now: Date = .now, calendar: Calendar = .current) -> [Challenge] {
        var done = completedChallenges(for: ownerID)
        let fresh = ChallengeEngine.statuses(runs: runs, now: now, calendar: calendar)
            .filter { $0.isCompleted && !done.contains(challengeKey($0.challenge, now: now, calendar: calendar)) }
            .map(\.challenge)
        guard !fresh.isEmpty else { return [] }
        fresh.forEach { done.insert(challengeKey($0, now: now, calendar: calendar)) }
        UserDefaults.standard.set(done.sorted(), forKey: challengesKey(ownerID))
        return fresh
    }

    /// 회원 탈퇴 시 그 계정의 캐시만 삭제
    static func reset(for ownerID: UUID) {
        UserDefaults.standard.removeObject(forKey: badgesKey(ownerID))
        UserDefaults.standard.removeObject(forKey: challengesKey(ownerID))
    }
}
