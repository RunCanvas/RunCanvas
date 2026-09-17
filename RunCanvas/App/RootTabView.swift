import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(AuthService.self) private var auth
    @Environment(RunCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator
        LevelThemedTabs(ownerID: auth.userID)
            .onChange(of: auth.userID, initial: true) { _, id in
                coordinator.ownerID = id
            }
            .fullScreenCover(isPresented: $coordinator.showsWatchRun) {
                NavigationStack {
                    RunView(startImmediately: false)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("닫기") { coordinator.showsWatchRun = false }
                            }
                        }
                }
            }
            .alert("iPhone 러닝을 시작하지 못했어요", isPresented: Binding(
                get: { coordinator.watchStartError != nil },
                set: { if !$0 { coordinator.watchStartError = nil } }
            )) {
                Button("확인", role: .cancel) { coordinator.watchStartError = nil }
            } message: {
                Text(coordinator.watchStartError ?? "")
            }
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
            Tab("런꾸", systemImage: "photo.on.rectangle") { CanvasHomeView() }
            Tab("설정", systemImage: "gearshape") { SettingsView() }
        }
        .tint(.primary)
        .environment(\.levelTier, tier)   // PrimaryButton·홈 러닝 시작 버튼만 레벨 색을 쓴다
    }
}

#Preview {
    let container = try! ModelContainer(for: Run.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let watch = WatchConnectivityService()
    RootTabView()
        .environment(AuthService())
        .environmentObject(watch)
        .environment(RunCoordinator(watch: watch, context: container.mainContext, session: RunSession()))
        .modelContainer(container)
}
