import Foundation

/// 스트라바식 참여형 챌린지 — 서버 없이 자동 참여, 로컬 기록으로 진행도 계산.
/// id는 완료 트로피 저장 키("\(id)@2026-08")에 쓰이므로 바꾸지 말 것. 월간 챌린지는 매달, 주간은 매주 새로 시작한다.
struct Challenge: Identifiable, Equatable {
    enum Period { case week, month }
    enum Metric { case totalDistance, runCount, longestRun }

    let id: String
    let title: String
    let period: Period
    let metric: Metric
    let target: Double   // 거리=미터, 횟수=회

    static let all: [Challenge] = [
        Challenge(id: "week_3runs", title: "이번 주 3번 달리기", period: .week, metric: .runCount, target: 3),
        Challenge(id: "month_50km", title: "이번 달 50km", period: .month, metric: .totalDistance, target: 50_000),
        Challenge(id: "month_8runs", title: "이번 달 8번 달리기", period: .month, metric: .runCount, target: 8),
        Challenge(id: "month_10k", title: "이번 달 10K 한 번", period: .month, metric: .longestRun, target: 10_000),
    ]
}
