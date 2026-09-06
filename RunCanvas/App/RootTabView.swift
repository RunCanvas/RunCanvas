import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        LevelThemedTabs(ownerID: auth.userID)
    }
}

/// 계정 누적 거리 → 레벨 → 주요 버튼 색. 기록이 쌓여 레벨이 오르면 버튼 색이 바뀐다.
private struct LevelThemedTabs: View {
    @Query private var runs: [Run]

    init(ownerID: UUID?) {
        let owner = ownerID ?? .noOwner
        _runs = Query(filter: #Predicate<Run> { $0.ownerID == owner })
    }

    private var tier: Level.Tier {
        Level.forTotalDistance(runs.reduce(0) { $0 + $1.distanceMeters }).tier
    }

    var body: some View {
        TabView {
            Tab("홈", systemImage: "house") { RunnerHomeView() }
            Tab("기록", systemImage: "chart.bar") { RunStatsView() }
            Tab("런꾸", systemImage: "photo.on.rectangle") { CanvasFlowView() }
            Tab("설정", systemImage: "gearshape") { SettingsView() }
        }
        .tint(.primary)
        .environment(\.levelTier, tier)   // PrimaryButton·홈 러닝 시작 버튼만 레벨 색을 쓴다
    }
}

#Preview {
    RootTabView()
        .environment(AuthService())
        .modelContainer(for: Run.self, inMemory: true)
}
