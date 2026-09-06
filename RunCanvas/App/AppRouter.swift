import SwiftUI
import SwiftData

/// 앱 루트 분기: 스플래시 → (세션 없음) 로그인 / (세션 있음, 프로필 없음) 프로필 설정 / (둘 다) 메인 탭
struct AppRouter: View {
    @State private var auth = AuthService()
    @State private var hasProfile = false
    @State private var isLoading = true
    @State private var didShowSplash = false
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if isLoading {
                SplashView()
            } else if !auth.isSignedIn {
                LoginView()
            } else if !hasProfile {
                ProfileSetupView { hasProfile = true }
            } else {
                RootTabView()
            }
        }
        .environment(auth)
        .task(id: auth.userID) { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { syncIfPossible() }
        }
    }

    /// 프로필이 확인된 마지막 계정 — 오프라인에서 "프로필 없음"과 구별하기 위해
    private static let profiledUserKey = "profiledUserID"

    /// 안 올라간 기록·뱃지를 서버로 (로그인 상태에서만, 실패는 조용히)
    private func syncIfPossible() {
        guard auth.canSync, hasProfile, let id = auth.userID else { return }
        Task { await SyncService.sync(context: context, ownerID: id) }
    }

    private func load() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestSkipLogin") {
            let testUser = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!
            if ProcessInfo.processInfo.arguments.contains("-uiTestReset") {
                try? context.delete(model: Run.self, where: #Predicate { $0.ownerID == testUser })
                try? context.save()
                BadgeStore.reset(for: testUser)
                // 중단된 러닝 체크포인트도 지운다 — 안 지우면 실패한 실행이 남긴 파일 때문에
                // 다음 실행부터 "이전 러닝이 중단됐어요" 알럿이 떠서 러닝이 시작되지 않는다
                RunSession.discardRecoverable()
            }
            if ProcessInfo.processInfo.arguments.contains("-uiTestSeedRun") {
                let existing = (try? context.fetch(FetchDescriptor<Run>(predicate: #Predicate { $0.ownerID == testUser }))) ?? []
                if existing.isEmpty {
                    let start = Date().addingTimeInterval(-700)
                    let route = (0..<24).map { index in
                        RoutePoint(
                            latitude: 37.5445 + Double(index) * 0.00008,
                            longitude: 127.0374 + sin(Double(index) / 4) * 0.0003,
                            timestamp: start.addingTimeInterval(Double(index) * 25)
                        )
                    }
                    context.insert(Run(
                        ownerID: testUser,
                        startedAt: start,
                        endedAt: start.addingTimeInterval(600),
                        distanceMeters: 1_250,
                        movingSeconds: 600,
                        calories: 77.7,
                        averageHeartRate: 148,
                        maxHeartRate: 172,
                        route: route
                    ))
                    try? context.save()
                }
            }
            auth.debugUserID = testUser
            hasProfile = true
            isLoading = false
            return
        }
        #endif
        isLoading = true
        let started = Date()
        let loadingID = auth.userID          // 이 load()가 담당하는 계정
        if let id = loadingID {
            do {
                let profile = try await ProfileService.fetchMine(userID: id)
                guard auth.userID == loadingID else { return }   // 그 사이 계정이 바뀌었으면 이 결과는 버린다
                profile?.cacheLocally()
                hasProfile = profile != nil
                UserDefaults.standard.set(profile != nil ? id.uuidString : "", forKey: Self.profiledUserKey)
            } catch {
                // 네트워크 오류를 "프로필 없음"으로 착각하면 기존 사용자가 오프라인에서 프로필 설정 화면에 갇힌다.
                // 마지막으로 확인된 계정이면 프로필이 있는 것으로 본다.
                guard auth.userID == loadingID else { return }
                hasProfile = UserDefaults.standard.string(forKey: Self.profiledUserKey) == id.uuidString
            }
        } else {
            hasProfile = false
        }
        if !didShowSplash {   // 첫 실행만 스플래시 최소 1초
            didShowSplash = true
            let remaining = 1.0 - Date().timeIntervalSince(started)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
        }
        guard auth.userID == loadingID else { return }
        isLoading = false
        syncIfPossible()
    }
}

#Preview {
    AppRouter()
}
