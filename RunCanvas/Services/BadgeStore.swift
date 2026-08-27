import Foundation

/// 획득한 뱃지(날짜 포함)와 완료한 챌린지를 로컬에 기억해 두고, 새 기록 뒤에 "이번에 새로 딴 것"만 골라낸다.
/// (서버 user_badges 업로드는 Phase 7 SyncService)
enum BadgeStore {
    private static let badgesKey = "earnedBadgeDates"      // [Badge.rawValue: 획득 시각(epoch)]
    private static let challengesKey = "completedChallenges" // ["month_50km@2026-08", ...]

    // MARK: 뱃지

    static var earnedDates: [Badge: Date] {
        get {
            let raw = UserDefaults.standard.dictionary(forKey: badgesKey) as? [String: Double] ?? [:]
            return raw.reduce(into: [:]) { result, pair in
                if let badge = Badge(rawValue: pair.key) { result[badge] = Date(timeIntervalSince1970: pair.value) }
            }
        }
        set {
            let raw = newValue.reduce(into: [String: Double]()) { $0[$1.key.rawValue] = $1.value.timeIntervalSince1970 }
            UserDefaults.standard.set(raw, forKey: badgesKey)
        }
    }

    static var earned: Set<Badge> { Set(earnedDates.keys) }

    /// 현재 기록으로 계산한 뱃지 중 아직 저장 안 된 것 → 지금 날짜로 저장하고 돌려준다 (Badge.allCases 순서)
    @discardableResult
    static func recordNewlyEarned(from runs: [BadgeRun], now: Date = .now, calendar: Calendar = .current) -> [Badge] {
        let current = BadgeEngine.earned(runs: runs, calendar: calendar)
        var dates = earnedDates
        let fresh = Badge.allCases.filter { current.contains($0) && dates[$0] == nil }
        guard !fresh.isEmpty else { return [] }
        fresh.forEach { dates[$0] = now }
        earnedDates = dates
        return fresh
    }

    // MARK: 챌린지

    static var completedChallenges: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: challengesKey) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: challengesKey) }
    }

    static func challengeKey(_ challenge: Challenge, now: Date = .now, calendar: Calendar = .current) -> String {
        "\(challenge.id)@\(ChallengeEngine.periodKey(challenge.period, now: now, calendar: calendar))"
    }

    /// 이번 기간에 새로 완료한 챌린지 → 저장하고 돌려준다
    @discardableResult
    static func recordCompletedChallenges(from runs: [BadgeRun], now: Date = .now, calendar: Calendar = .current) -> [Challenge] {
        var done = completedChallenges
        let fresh = ChallengeEngine.statuses(runs: runs, now: now, calendar: calendar)
            .filter { $0.isCompleted && !done.contains(challengeKey($0.challenge, now: now, calendar: calendar)) }
            .map(\.challenge)
        guard !fresh.isEmpty else { return [] }
        fresh.forEach { done.insert(challengeKey($0, now: now, calendar: calendar)) }
        completedChallenges = done
        return fresh
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: badgesKey)
        UserDefaults.standard.removeObject(forKey: challengesKey)
    }
}
