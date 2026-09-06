import Foundation

/// 런꾸 월말/연말 정산 집계 — 순수 함수. 입력은 BadgeRun이라 SwiftData 없이 테스트한다.
/// StatsEngine은 "지금이 속한 기간"만 다루므로, 지난 달·지난 해를 골라 보려면 기준 날짜를 받는 이쪽을 쓴다.
enum RecapEngine {
    enum Scope: String, CaseIterable, Identifiable {
        case month = "월말정산", year = "연말정산"
        var id: String { rawValue }

        var component: Calendar.Component { self == .month ? .month : .year }
    }

    /// 카드 한 장에 들어가는 값 전부. 기록이 없는 기간이면 title만 채워지고 나머지는 0/nil.
    struct Recap: Equatable {
        var title = ""                      // "2026년 8월" / "2026년"
        var totalMeters: Double = 0
        var count = 0
        var totalSeconds = 0
        var avgPaceSecondsPerKm: Double? = nil
        var longestRunMeters: Double = 0
        var activeDays = 0                  // 한 번이라도 달린 날 수 ("31일 중 12일")
        var busiestWeekday: String? = nil   // 가장 많이 뛴 요일 ("토")
    }

    /// 로케일과 무관하게 한글 고정 — index = weekday - 1 (그레고리력에서 1은 항상 일요일)
    private static let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    /// 기록이 하나라도 있는 달(해)의 시작 시각, 최신순. 기간 선택기가 이걸 그대로 쓴다.
    static func availableAnchors(runs: [BadgeRun], scope: Scope, calendar: Calendar = .current) -> [Date] {
        let starts = runs.compactMap { calendar.dateInterval(of: scope.component, for: $0.startedAt)?.start }
        return Array(Set(starts)).sorted(by: >)
    }

    static func title(for anchor: Date, scope: Scope, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: anchor)
        guard let year = parts.year else { return "" }
        return scope == .month ? "\(year)년 \(parts.month ?? 1)월" : "\(year)년"
    }

    /// anchor가 속한 달(해)의 집계. anchor는 그 기간 안의 아무 시각이어도 된다.
    static func recap(runs: [BadgeRun], scope: Scope, anchor: Date, calendar: Calendar = .current) -> Recap {
        var recap = Recap(title: title(for: anchor, scope: scope, calendar: calendar))
        guard let interval = calendar.dateInterval(of: scope.component, for: anchor) else { return recap }

        // 반열림 구간 — DateInterval.contains는 끝점을 포함해서 9/1 0시 기록이 8월·9월 양쪽에 잡힌다
        let range = interval.start..<interval.end
        let inRange = runs.filter { range.contains($0.startedAt) }
        guard !inRange.isEmpty else { return recap }

        recap.totalMeters = inRange.reduce(0) { $0 + $1.distanceMeters }
        recap.count = inRange.count
        recap.totalSeconds = inRange.reduce(0) { $0 + $1.movingSeconds }
        recap.avgPaceSecondsPerKm = RunMath.paceSecondsPerKm(distanceMeters: recap.totalMeters,
                                                             seconds: recap.totalSeconds)
        recap.longestRunMeters = inRange.map(\.distanceMeters).max() ?? 0
        recap.activeDays = Set(inRange.map { calendar.startOfDay(for: $0.startedAt) }).count
        recap.busiestWeekday = busiestWeekday(inRange, calendar: calendar)
        return recap
    }

    /// 횟수가 같으면 거리가 긴 요일, 그것도 같으면 앞선 요일(일→토). 같은 입력이면 결과가 흔들리지 않게 고정.
    private static func busiestWeekday(_ runs: [BadgeRun], calendar: Calendar) -> String? {
        guard !runs.isEmpty else { return nil }
        var stats = Array(repeating: (count: 0, meters: 0.0), count: 7)
        for run in runs {
            let index = calendar.component(.weekday, from: run.startedAt) - 1
            stats[index].count += 1
            stats[index].meters += run.distanceMeters
        }
        // max(by:)는 동점이면 앞쪽을 남긴다
        let best = (0..<7).max { (stats[$0].count, stats[$0].meters) < (stats[$1].count, stats[$1].meters) }
        return best.map { weekdaySymbols[$0] }
    }
}
