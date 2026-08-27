import Foundation

/// 지금까지 획득한 뱃지를 로컬에 기억해 두고, 새 기록 뒤에 "이번에 새로 딴 뱃지"만 골라낸다.
/// (서버 user_badges 업로드는 Phase 7 SyncService)
enum BadgeStore {
    private static let key = "earnedBadges"

    static var earned: Set<Badge> {
        get {
            let raw = UserDefaults.standard.string(forKey: key) ?? ""
            return Set(raw.split(separator: ",").compactMap { Badge(rawValue: String($0)) })
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue).sorted().joined(separator: ","), forKey: key)
        }
    }

    /// 현재 기록으로 계산한 뱃지 중 아직 저장 안 된 것 → 저장하고 돌려준다 (Badge.allCases 순서)
    @discardableResult
    static func recordNewlyEarned(from runs: [BadgeRun], calendar: Calendar = .current) -> [Badge] {
        let current = BadgeEngine.earned(runs: runs, calendar: calendar)
        let fresh = Badge.allCases.filter { current.contains($0) && !earned.contains($0) }
        if !fresh.isEmpty { earned = current }
        return fresh
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
