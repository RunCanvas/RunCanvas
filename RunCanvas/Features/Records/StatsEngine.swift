import Foundation

/// 기록 탭 통계 — 순수 함수. 입력은 BadgeRun(SwiftData와 분리)이라 유닛 테스트가 쉽다.
enum StatsEngine {
    enum Period: String, CaseIterable, Identifiable {
        case week = "주", month = "월", year = "년"
        var id: String { rawValue }

        var component: Calendar.Component {
            switch self {
            case .week: .weekOfYear
            case .month: .month
            case .year: .year
            }
        }
    }

    struct Summary: Equatable {
        var totalMeters: Double = 0
        var count = 0
        var totalSeconds = 0
        var avgPaceSecondsPerKm: Double? = nil
    }

    /// 차트 막대 하나 (주=요일 7개, 월=일별, 년=월 12개). 기록 없는 구간도 0으로 포함해 x축이 고정된다.
    struct Bucket: Identifiable, Equatable {
        let id: Int
        let label: String
        var distanceMeters: Double
    }

    /// 지금이 속한 기간 (주는 calendar.firstWeekday 기준 — ChallengeEngine과 동일)
    static func range(_ period: Period, now: Date, calendar: Calendar = .current) -> Range<Date> {
        let interval = calendar.dateInterval(of: period.component, for: now)!
        return interval.start..<interval.end
    }

    static func summary(runs: [BadgeRun], period: Period, now: Date = .now, calendar: Calendar = .current) -> Summary {
        let range = range(period, now: now, calendar: calendar)
        let inRange = runs.filter { range.contains($0.startedAt) }
        let meters = inRange.reduce(0) { $0 + $1.distanceMeters }
        let seconds = inRange.reduce(0) { $0 + $1.movingSeconds }
        return Summary(totalMeters: meters, count: inRange.count, totalSeconds: seconds,
                       avgPaceSecondsPerKm: RunMath.paceSecondsPerKm(distanceMeters: meters, seconds: seconds))
    }

    static func buckets(runs: [BadgeRun], period: Period, now: Date = .now, calendar: Calendar = .current) -> [Bucket] {
        let range = range(period, now: now, calendar: calendar)
        var result: [Bucket]
        switch period {
        case .week:
            // 로케일과 무관하게 한글 고정 — 영어 로케일의 T/S처럼 라벨이 겹치면 차트가 막대를 합쳐버린다
            let symbols = ["일", "월", "화", "수", "목", "금", "토"]   // index = weekday - 1
            result = (0..<7).map { i in
                Bucket(id: i, label: symbols[(calendar.firstWeekday - 1 + i) % 7], distanceMeters: 0)
            }
        case .month:
            let days = calendar.range(of: .day, in: .month, for: now)!.count
            result = (0..<days).map { Bucket(id: $0, label: "\($0 + 1)", distanceMeters: 0) }
        case .year:
            result = (0..<12).map { Bucket(id: $0, label: "\($0 + 1)월", distanceMeters: 0) }
        }
        for run in runs where range.contains(run.startedAt) {
            let index: Int
            switch period {
            case .week:
                index = calendar.dateComponents([.day], from: calendar.startOfDay(for: range.lowerBound),
                                                to: calendar.startOfDay(for: run.startedAt)).day!
            case .month: index = calendar.component(.day, from: run.startedAt) - 1
            case .year: index = calendar.component(.month, from: run.startedAt) - 1
            }
            if result.indices.contains(index) { result[index].distanceMeters += run.distanceMeters }
        }
        return result
    }

    /// 차트 폭에 맞게 x축 라벨을 고르되 첫·마지막 날짜는 항상 보여 준다.
    /// 월간 28~31개와 연간 12개를 전부 그리면 작은 iPhone에서 글자가 겹친다.
    static func axisLabels(buckets: [Bucket], period: Period) -> [String] {
        let maximumCount = switch period {
        case .week: 7
        case .month: 5
        case .year: 6
        }
        guard buckets.count > maximumCount, maximumCount > 1 else { return buckets.map(\.label) }

        let lastIndex = buckets.count - 1
        let indices = (0..<maximumCount).map { position in
            Int((Double(position) * Double(lastIndex) / Double(maximumCount - 1)).rounded())
        }
        return indices.map { buckets[$0].label }
    }
}
