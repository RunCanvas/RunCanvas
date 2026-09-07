import Foundation

/// 챌린지 진행도 — 기간(이번 주/이번 달) 안의 기록만 센다. 순수 함수.
enum ChallengeEngine {
    struct Status: Equatable {
        let challenge: Challenge
        let value: Double
        let daysLeft: Int
        var isCompleted: Bool { value >= challenge.target }
        var fraction: Double { min(value / challenge.target, 1) }
    }

    /// "2026-08" / "2026-W35" — 완료 트로피 저장 키에 쓴다
    static func periodKey(_ period: Challenge.Period, now: Date, calendar: Calendar = .current) -> String {
        // 저장 키의 연도는 기기에서 일본력·불력을 골라도 바뀌면 안 된다.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        gregorian.firstWeekday = calendar.firstWeekday
        gregorian.minimumDaysInFirstWeek = calendar.minimumDaysInFirstWeek
        switch period {
        case .month:
            let c = gregorian.dateComponents([.year, .month], from: now)
            return String(format: "%04d-%02d", c.year!, c.month!)
        case .week:
            let c = gregorian.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            return String(format: "%04d-W%02d", c.yearForWeekOfYear!, c.weekOfYear!)
        }
    }

    static func periodRange(_ period: Challenge.Period, now: Date, calendar: Calendar = .current) -> Range<Date> {
        let component: Calendar.Component = period == .month ? .month : .weekOfYear
        let interval = calendar.dateInterval(of: component, for: now)!
        return interval.start..<interval.end
    }

    static func status(_ challenge: Challenge, runs: [BadgeRun], now: Date = .now, calendar: Calendar = .current) -> Status {
        let range = periodRange(challenge.period, now: now, calendar: calendar)
        let inPeriod = runs.filter { range.contains($0.startedAt) }
        let value: Double = switch challenge.metric {
        case .totalDistance: inPeriod.reduce(0) { $0 + $1.distanceMeters }
        case .runCount: Double(inPeriod.count)
        case .longestRun: inPeriod.map(\.distanceMeters).max() ?? 0
        }
        let daysLeft = max(calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: range.upperBound).day ?? 0, 0)
        return Status(challenge: challenge, value: value, daysLeft: daysLeft)
    }

    static func statuses(runs: [BadgeRun], now: Date = .now, calendar: Calendar = .current) -> [Status] {
        Challenge.all.map { status($0, runs: runs, now: now, calendar: calendar) }
    }
}
