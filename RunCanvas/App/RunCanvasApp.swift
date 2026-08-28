import SwiftUI

@main
struct RunCanvasApp: App {
    @StateObject private var watchConnectivity = WatchConnectivityService()

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environmentObject(watchConnectivity)
        }
            .modelContainer(for: Run.self)
    }
}
