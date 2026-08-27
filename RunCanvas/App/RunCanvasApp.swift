import SwiftUI

@main
struct RunCanvasApp: App {
    var body: some Scene {
        WindowGroup { AppRouter() }
            .modelContainer(for: Run.self)
    }
}
