import SwiftUI
import SwiftData

@main
struct RunCanvasApp: App {
    private let container: ModelContainer
    @StateObject private var watchConnectivity: WatchConnectivityService
    /// 러닝 세션·워치 콜백은 앱 수명 — 화면을 벗어나도 워치 명령이 살아 있어야 한다
    @State private var runCoordinator: RunCoordinator

    init() {
        let container = try! ModelContainer(for: Run.self)
        let watch = WatchConnectivityService()
        self.container = container
        _watchConnectivity = StateObject(wrappedValue: watch)
        _runCoordinator = State(initialValue: RunCoordinator(
            watch: watch,
            context: container.mainContext,
            session: RunSession(health: HealthService(), coach: VoiceCoach())
        ))
    }

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environmentObject(watchConnectivity)
                .environment(runCoordinator)
        }
            .modelContainer(container)
    }
}
