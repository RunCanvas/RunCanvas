import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("홈", systemImage: "house") { HomeView() }
            Tab("기록", systemImage: "chart.bar") { RecordsView() }
            Tab("런구", systemImage: "photo.on.rectangle") { CanvasView() }
            Tab("설정", systemImage: "gearshape") { SettingsView() }
        }
    }
}

#Preview {
    RootTabView()
}
