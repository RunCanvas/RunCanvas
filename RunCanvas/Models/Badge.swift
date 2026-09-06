import Foundation

/// 획득 뱃지(NRC 트로피 방식). rawValue는 서버 user_badges.badge·로컬 캐시에 그대로 저장되므로 바꾸지 말 것.
enum Badge: String, CaseIterable, Codable, Identifiable {
    // 한 번에 달린 거리
    case firstRun, fiveK, tenK, fifteenK, halfMarathon, marathon
    // 누적 거리
    case total50km, total100km, total250km, total500km, total1000km
    // 연속 일수
    case streak3, streak7, streak30
    // 러닝 횟수
    case runs10, runs50, runs100
    // 시간대
    case earlyBird, nightRunner

    var id: String { rawValue }

    /// Assets.xcassets/Badges 의 일러스트 이름. 없으면 symbolName 으로 대체 (BadgeArt)
    var imageName: String { "badge_\(rawValue)" }

    enum Category: String, CaseIterable, Identifiable {
        case distance = "거리"
        case total = "누적"
        case streak = "연속"
        case count = "횟수"
        case time = "시간대"
        var id: String { rawValue }
    }

    var category: Category {
        switch self {
        case .firstRun, .fiveK, .tenK, .fifteenK, .halfMarathon, .marathon: .distance
        case .total50km, .total100km, .total250km, .total500km, .total1000km: .total
        case .streak3, .streak7, .streak30: .streak
        case .runs10, .runs50, .runs100: .count
        case .earlyBird, .nightRunner: .time
        }
    }

    var title: String {
        switch self {
        case .firstRun: "첫 러닝"
        case .fiveK: "5K"
        case .tenK: "10K"
        case .fifteenK: "15K"
        case .halfMarathon: "하프 마라톤"
        case .marathon: "풀 마라톤"
        case .total50km: "50km"
        case .total100km: "100km"
        case .total250km: "250km"
        case .total500km: "500km"
        case .total1000km: "1,000km"
        case .streak3: "3일 연속"
        case .streak7: "7일 연속"
        case .streak30: "30일 연속"
        case .runs10: "10회"
        case .runs50: "50회"
        case .runs100: "100회"
        case .earlyBird: "얼리버드"
        case .nightRunner: "나이트 러너"
        }
    }

    var detail: String {
        switch self {
        case .firstRun: "첫 러닝을 완주했어요"
        case .fiveK: "한 번에 5km 이상"
        case .tenK: "한 번에 10km 이상"
        case .fifteenK: "한 번에 15km 이상"
        case .halfMarathon: "한 번에 21.1km 이상"
        case .marathon: "한 번에 42.2km 이상"
        case .total50km: "누적 50km"
        case .total100km: "누적 100km"
        case .total250km: "누적 250km"
        case .total500km: "누적 500km"
        case .total1000km: "누적 1,000km"
        case .streak3: "3일 연속으로 달렸어요"
        case .streak7: "7일 연속으로 달렸어요"
        case .streak30: "30일 연속으로 달렸어요"
        case .runs10: "러닝 10회"
        case .runs50: "러닝 50회"
        case .runs100: "러닝 100회"
        case .earlyBird: "아침 6시 전에 달렸어요"
        case .nightRunner: "밤 9시 이후에 달렸어요"
        }
    }

    var symbolName: String {
        switch category {
        case .distance: self == .firstRun ? "figure.run" : (self == .halfMarathon || self == .marathon ? "medal.fill" : "flag.checkered")
        case .total: "road.lanes"
        case .streak: "flame.fill"
        case .count: "repeat"
        case .time: self == .earlyBird ? "sunrise.fill" : "moon.stars.fill"
        }
    }

    /// 진행도 계산용 목표값. 단위는 카테고리별로 다름(거리·누적=미터, 연속=일, 횟수=회, 시간대=1회)
    var target: Double {
        switch self {
        case .firstRun: 1
        case .fiveK: 5_000
        case .tenK: 10_000
        case .fifteenK: 15_000
        case .halfMarathon: 21_097.5
        case .marathon: 42_195
        case .total50km: 50_000
        case .total100km: 100_000
        case .total250km: 250_000
        case .total500km: 500_000
        case .total1000km: 1_000_000
        case .streak3: 3
        case .streak7: 7
        case .streak30: 30
        case .runs10: 10
        case .runs50: 50
        case .runs100: 100
        case .earlyBird, .nightRunner: 1
        }
    }
}
