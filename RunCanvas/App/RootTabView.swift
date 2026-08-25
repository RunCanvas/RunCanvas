import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("홈", systemImage: "house") { RunnerHomeView() }
            Tab("기록", systemImage: "chart.bar") { RunStatsView() }
            Tab("런꾸", systemImage: "photo.on.rectangle") { RunDecorateView() }
            Tab("설정", systemImage: "gearshape") { ProfileView() }
        }
    }
}

#Preview {
    RootTabView()
        .environment(AuthService())
}
