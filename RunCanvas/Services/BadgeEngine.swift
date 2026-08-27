import Foundation

/// 뱃지·레벨·최고 기록 계산에 필요한 최소 정보.
/// Phase 1의 SwiftData `Run`에서 `BadgeRun(startedAt:distanceMeters:movingSeconds:)`로 매핑한다.
struct BadgeRun: Hashable {
    var startedAt: Date
    var distanceMeters: Double
    var movingSeconds: Int
}

/// 최고 기록 (NRC의 "기록" 섹션)
struct PersonalBests: Equatable {
    var longestRunMeters: Double = 0
    var bestPaceSecondsPerKm: Double? = nil   // 1km 이상 달린 기록 중 최고 페이스
    var longestStreakDays: Int = 0
    var totalRuns: Int = 0
    var totalMeters: Double = 0
}

/// 기록 배열 → 획득 뱃지·진행도·최고 기록. 서버 없이 순수 계산. 같은 입력이면 항상 같은 결과.
enum BadgeEngine {
    static func totalDistance(_ runs: [BadgeRun]) -> Double {
        runs.reduce(0) { $0 + $1.distanceMeters }
    }

    /// 뱃지별 현재 값 (목표는 `badge.target`). 잠긴 뱃지의 "3/7일" 표시에 쓴다.
    static func progressValue(for badge: Badge, runs: [BadgeRun], calendar: Calendar = .current) -> Double {
        switch badge.category {
        case .distance:
            badge == .firstRun ? Double(min(runs.count, 1)) : (runs.map(\.distanceMeters).max() ?? 0)
        case .total:
            totalDistance(runs)
        case .streak:
            Double(longestDailyStreak(runs, calendar: calendar))
        case .count:
            Double(runs.count)
        case .time:
            runs.contains { hourMatches(badge, $0.startedAt, calendar: calendar) } ? 1 : 0
        }
    }

    static func isEarned(_ badge: Badge, runs: [BadgeRun], calendar: Calendar = .current) -> Bool {
        progressValue(for: badge, runs: runs, calendar: calendar) >= badge.target
    }

    static func earned(runs: [BadgeRun], calendar: Calendar = .current) -> Set<Badge> {
        Set(Badge.allCases.filter { isEarned($0, runs: runs, calendar: calendar) })
    }

    static func personalBests(_ runs: [BadgeRun], calendar: Calendar = .current) -> PersonalBests {
        PersonalBests(
            longestRunMeters: runs.map(\.distanceMeters).max() ?? 0,
            bestPaceSecondsPerKm: runs
                .filter { $0.distanceMeters >= 1_000 && $0.movingSeconds > 0 }
                .map { Double($0.movingSeconds) / ($0.distanceMeters / 1_000) }
                .min(),
            longestStreakDays: longestDailyStreak(runs, calendar: calendar),
            totalRuns: runs.count,
            totalMeters: totalDistance(runs)
        )
    }

    /// 하루에 한 번 이상 달린 날이 연속으로 며칠인지 (최장 구간)
    static func longestDailyStreak(_ runs: [BadgeRun], calendar: Calendar = .current) -> Int {
        let days = Set(runs.map { calendar.startOfDay(for: $0.startedAt) }).sorted()
        var best = 0, current = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                current += 1
            } else {
                current = 1
            }
            best = max(best, current)
            previous = day
        }
        return best
    }

    private static func hourMatches(_ badge: Badge, _ date: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        switch badge {
        case .earlyBird: return hour < 6
        case .nightRunner: return hour >= 21
        default: return false
        }
    }
}
