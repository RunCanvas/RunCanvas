import SwiftUI

@main
struct RunCanvasWatchApp: App {
    // 왜 앱에서 소유: init 이 WCSession 델리게이트를 잡고 살아 있는 워크아웃을 되찾는다.
    // 뷰의 @State 기본값은 뷰가 다시 만들어질 때마다 평가돼, 버려질 인스턴스가 델리게이트를 빼앗을 수 있다.
    @State private var workout = WatchWorkoutManager()

    var body: some Scene {
        WindowGroup {
            WatchRunView(workout: workout)
        }
    }
}
