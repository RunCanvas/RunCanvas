import SwiftUI
import SwiftData

/// 앱 루트 분기: 스플래시 → (세션 없음) 로그인 / (세션 있음, 프로필 없음) 프로필 설정 / (둘 다) 메인 탭
struct AppRouter: View {
    @State private var auth = AuthService()
    @State private var hasProfile = false
    @State private var isLoading = true
    @State private var didShowSplash = false
    @State private var loadedUserID: UUID?
    /// 진행 중인 동기화. 포그라운드 전환이 겹쳤을 때 두 번 도는 걸 막는다 (syncIfPossible 주석 참고)
    @State private var syncTask: Task<Void, Never>?
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if isLoading || loadedUserID != auth.userID {
                if didShowSplash {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground))
                } else {
                    SplashView()
                }
            } else if !auth.isSignedIn {
                LoginView()
            } else if !hasProfile {
                ProfileSetupView {
                    hasProfile = true
                    markProfiled(auth.userID)
                }
            } else {
                RootTabView()
            }
        }
        .environment(auth)
        .task(id: auth.userID) { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { syncIfPossible() }
        }
        .onOpenURL { auth.handleOpenURL($0) }
    }

    /// 프로필이 확인된 마지막 계정 — 오프라인에서 "프로필 없음"과 구별하기 위해
    private static let profiledUserKey = "profiledUserID"

    /// 안 올라간 기록·뱃지를 서버로 (로그인 상태에서만, 실패는 조용히)
    ///
    /// 왜 진행 중이면 건너뛰는가: importMissingRuns 는 로컬 스냅샷을 읽고 **그다음에** 긴 await(90일치
    /// 건강 앱 쿼리)를 탄다. 포그라운드 전환이 겹쳐 두 번 들어오면 둘 다 같은 스냅샷을 보고 중복 판정을
    /// 통과해, 같은 워크아웃이 서로 다른 Run.id 로 두 번 저장된다(@Attribute(.unique) 가 막지 못한다).
    /// 설치 직후 첫 실행이 가장 위험하다 — 그때 쿼리가 제일 길다.
    /// SyncService 는 내부에 syncTail 이 있지만 그 앞의 importMissingRuns 는 보호받지 못한다.
    private func syncIfPossible() {
        guard auth.canSync, hasProfile, let id = auth.userID else { return }
        guard syncTask == nil else { return }
        syncTask = Task {
            defer { syncTask = nil }
            // 왜 가져오기가 먼저: 폰 앱이 꺼진 채 워치로 뛴 러닝은 건강 앱에만 있다.
            // 여기서 기록으로 만들어 둬야 이어지는 sync 가 그것까지 서버에 올린다.
            await HealthImport.importMissingRuns(context: context, ownerID: id, health: HealthService())
            await SyncService.sync(context: context, ownerID: id)
        }
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
            loadedUserID = testUser
            isLoading = false
            return
        }
        #endif
        isLoading = true
        let started = Date()
        let loadingID = auth.userID          // 이 load()가 담당하는 계정
        var didAttemptInitialRestore = false
        if let id = loadingID {
            let wasProfiledOnThisDevice = UserDefaults.standard.string(forKey: Self.profiledUserKey) == id.uuidString
            do {
                let profile = try await ProfileService.fetchMine(userID: id)
                guard auth.userID == loadingID else { return }   // 그 사이 계정이 바뀌었으면 이 결과는 버린다
                profile?.cacheLocally()
                hasProfile = profile != nil
                markProfiled(profile == nil ? nil : id)
                if profile != nil, !wasProfiledOnThisDevice {
                    didAttemptInitialRestore = true
                    // 왜: 새 기기에서 빈 홈을 먼저 보여주지 않되, 서버 지연 때문에 라우팅이 무한히 막히지는 않게 한다.
                    try? await withTimeoutValue(seconds: 10) {
                        await SyncService.pullMissing(context: context, ownerID: id)
                    }
                }
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
            let remaining = 1.0 - Date().timeIntervalSince(started)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            didShowSplash = true
        }
        guard auth.userID == loadingID else { return }
        loadedUserID = loadingID
        isLoading = false
        if !didAttemptInitialRestore { syncIfPossible() }
    }

    private func markProfiled(_ id: UUID?) {
        UserDefaults.standard.set(id?.uuidString ?? "", forKey: Self.profiledUserKey)
    }
}

#Preview {
    AppRouter()
}
