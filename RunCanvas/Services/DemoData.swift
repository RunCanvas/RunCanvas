import Foundation
import SwiftData

/// 데모 계정에 채워 넣는 기록. App Store 심사자는 Apple·Google·카카오 계정이 없어
/// 소셜 로그인만으로는 앱에 들어올 수 없으므로(지침 2.1), 로그인 없이 둘러볼 수 있는 길을 둔다.
/// UI 테스트도 같은 계정·같은 시드를 쓴다.
///
/// 서버로 가지 않는다 — `AuthService.canSync` 가 데모에서 false 라 동기화가 통째로 건너뛰어진다.
enum DemoData {
    /// 이미 기록이 있으면 아무것도 하지 않는다. 심사자가 러닝을 직접 해 봐도 시드가 덮어쓰지 않는다.
    @MainActor
    static func seedIfNeeded(context: ModelContext, runCount: Int = 5) {
        let owner = AuthService.demoAccountID
        let existing = (try? context.fetch(
            FetchDescriptor<Run>(predicate: #Predicate { $0.ownerID == owner })
        )) ?? []
        guard existing.isEmpty else { return }

        for sample in samples.prefix(runCount) {
            context.insert(run(sample, ownerID: owner))
        }
        try? context.save()

        // 홈 인사말이 "러너 님"으로 비어 보이지 않게. 사용자가 이미 값을 넣었으면 건드리지 않는다.
        let defaults = UserDefaults.standard
        if (defaults.string(forKey: "userNickname") ?? "").isEmpty {
            defaults.set("데모", forKey: "userNickname")
        }
    }

    /// (며칠 전, 거리 m, 이동 초, 평균 심박, 최대 심박)
    /// 레벨·뱃지·통계·런꾸가 전부 채워져 보이도록 거리와 날짜를 흩어 둔다.
    private static let samples: [(daysAgo: Int, meters: Double, seconds: Int, avgHR: Double, maxHR: Double)] = [
        (1, 5_120, 1_720, 148, 171),
        (3, 10_240, 3_560, 152, 178),
        (5, 3_050, 1_020, 141, 160),
        (8, 21_100, 7_980, 155, 182),
        (12, 7_400, 2_510, 149, 174)
    ]

    @MainActor
    private static func run(
        _ sample: (daysAgo: Int, meters: Double, seconds: Int, avgHR: Double, maxHR: Double),
        ownerID: UUID
    ) -> Run {
        // 아침 7시 출발로 고정 — 시각이 제각각이면 "이른 새벽" 뱃지가 들쭉날쭉 붙는다
        let day = Calendar.appGregorian.date(byAdding: .day, value: -sample.daysAgo, to: .now) ?? .now
        let start = Calendar.appGregorian.date(bySettingHour: 7, minute: 10, second: 0, of: day) ?? day
        return Run(
            ownerID: ownerID,
            startedAt: start,
            endedAt: start.addingTimeInterval(Double(sample.seconds)),
            distanceMeters: sample.meters,
            movingSeconds: sample.seconds,
            calories: RunMath.calories(distanceMeters: sample.meters, weightKg: 62),
            averageHeartRate: sample.avgHR,
            maxHeartRate: sample.maxHR,
            route: route(meters: sample.meters, from: start, seconds: sample.seconds)
        )
    }

    /// 서울숲 근처를 도는 완만한 경로. 홈 지도와 런꾸 경로 스티커가 비어 보이지 않게 한다.
    private static func route(meters: Double, from start: Date, seconds: Int) -> [RoutePoint] {
        let count = max(24, min(240, Int(meters / 50)))
        // 거리에 맞춰 반경을 키운다 — 21km 기록이 5km와 같은 크기로 그려지면 어색하다
        let radius = 0.0016 * (meters / 5_000)
        return (0..<count).map { index in
            let t = Double(index) / Double(count)
            let angle = t * 2 * .pi * 1.6           // 한 바퀴 반 — 시작·종료 점이 겹치지 않는다
            return RoutePoint(
                latitude: 37.5445 + radius * sin(angle) + 0.0004 * sin(angle * 5),
                longitude: 127.0374 + radius * cos(angle) * 1.25,
                timestamp: start.addingTimeInterval(t * Double(seconds))
            )
        }
    }
}
