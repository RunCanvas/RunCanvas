import Foundation

/// 누적 거리로 정해지는 러너 레벨 — NRC처럼 레벨 이름이 색상이다.
/// 옐로 0 → 오렌지 50km → 그린 250km → 블루 1,000km → 퍼플 2,500km → 블랙 5,000km → 볼트 15,000km
struct Level: Equatable {
    enum Tier: Int, CaseIterable {
        case yellow, orange, green, blue, purple, black, volt

        var title: String {
            switch self {
            case .yellow: "옐로"
            case .orange: "오렌지"
            case .green: "그린"
            case .blue: "블루"
            case .purple: "퍼플"
            case .black: "블랙"
            case .volt: "볼트"
            }
        }

        var thresholdMeters: Double {
            switch self {
            case .yellow: 0
            case .orange: 50_000
            case .green: 250_000
            case .blue: 1_000_000
            case .purple: 2_500_000
            case .black: 5_000_000
            case .volt: 15_000_000
            }
        }

        var next: Tier? { Tier(rawValue: rawValue + 1) }
    }

    let tier: Tier
    let totalMeters: Double

    static func forTotalDistance(_ meters: Double) -> Level {
        let tier = Tier.allCases.last { meters >= $0.thresholdMeters } ?? .yellow
        return Level(tier: tier, totalMeters: max(meters, 0))
    }

    var number: Int { tier.rawValue + 1 }
    var title: String { tier.title }
    var nextTier: Tier? { tier.next }

    /// 현재 구간 안에서의 진행률 0...1 (마지막 레벨은 1)
    var progress: Double {
        guard let next = tier.next else { return 1 }
        let span = next.thresholdMeters - tier.thresholdMeters
        return min(max((totalMeters - tier.thresholdMeters) / span, 0), 1)
    }

    /// 다음 레벨까지 남은 거리(미터). 마지막 레벨은 nil
    var remainingMeters: Double? {
        tier.next.map { max($0.thresholdMeters - totalMeters, 0) }
    }
}
