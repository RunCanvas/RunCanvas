import Foundation
import OSLog
import Observation
import Supabase

/// Supabase Auth 세션 상태. 구글·카카오는 Supabase OAuth(웹) 플로우, Apple은 네이티브 id_token — 외부 SDK 없음.
@MainActor
@Observable
final class AuthService {
    private static let log = Logger(subsystem: "com.daun1997.RunCanvas", category: "auth")
    private(set) var session: Session?
    /// 현재 계정에 연결된 로그인 방법들 (provider: "apple" / "google" / "kakao")
    private(set) var identities: [UserIdentity] = []
    /// 탈퇴 직후 로그인 화면이 안내 알럿을 띄우기 위한 1회성 플래그 (알럿이 닫히며 false로 돌아감)
    var didDeleteAccount = false

    /// 로그인 없이 앱을 둘러보는 고정 계정. 두 곳에서 쓴다 —
    /// UI 테스트(`-uiTestSkipLogin`)와 **App Store 심사용 데모 모드**.
    ///
    /// 심사자는 Apple·Google·카카오 계정이 없어 소셜 로그인만으로는 앱에 들어올 수 없다
    /// (심사 지침 2.1이 데모 계정이나 데모 모드를 요구한다). 릴리즈 빌드에도 있어야 하므로
    /// `#if DEBUG` 로 감싸지 않는다. 진입 방법은 LoginView 참고.
    private(set) var demoUserID: UUID?
    var isDemo: Bool { demoUserID != nil }

    var userID: UUID? { demoUserID ?? session?.user.id }
    var isSignedIn: Bool { demoUserID != nil || session != nil }
    /// 서버 동기화 가능: 실제 세션이 있고 데모 계정이 아닐 때.
    /// 데모 기록이 서버로 올라가면 안 된다 — 기기 안에서만 산다.
    var canSync: Bool { demoUserID == nil && session != nil }

    /// 심사·UI 테스트용 고정 계정. 값이 고정이라 앱을 다시 열어도 같은 기록을 본다.
    static let demoAccountID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!

    func enterDemo() {
        guard session == nil else { return }   // 진짜 로그인 중이면 무시
        demoUserID = Self.demoAccountID
    }

    func exitDemo() {
        demoUserID = nil
        Profile.clearLocalCache()
    }

    private static let redirectURL = URL(string: "runcanvas://auth-callback")!
    /// 카카오 콘솔 동의항목과 정확히 일치해야 한다(불일치 시 invalid_scope). 이메일은 비즈 앱 전환 후 추가됨.
    private static let kakaoScopes = "profile_nickname profile_image account_email"
    @ObservationIgnored private var authStateTask: Task<Void, Never>?

    init() {
        session = supabase.auth.currentSession
        identities = session?.user.identities ?? []
        authStateTask = Task { [weak self] in
            for await (_, session) in supabase.auth.authStateChanges {
                guard !Task.isCancelled, let self else { return }
                self.session = session
                self.identities = session?.user.identities ?? []
            }
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    // MARK: - 로그인

    func signInWithGoogle() async throws { try await signIn(.google) }
    func signInWithKakao() async throws { try await signIn(.kakao, scopes: Self.kakaoScopes) }

    /// 네이티브 Sign in with Apple: 버튼이 받은 identityToken + 요청 때 쓴 원본 nonce.
    /// (버튼의 request.nonce에는 sha256(rawNonce)를 넣고, 여기엔 rawNonce를 넘긴다.)
    func signInWithApple(idToken: String, rawNonce: String) async throws {
        _ = try await supabase.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: rawNonce)
        )
    }

    private func signIn(_ provider: Provider, scopes: String? = nil) async throws {
        // ASWebAuthenticationSession이 runcanvas:// 콜백을 잡는다 (Info.plist URL 스킴, Supabase Redirect URL 등록됨)
        _ = try await supabase.auth.signInWithOAuth(provider: provider, redirectTo: Self.redirectURL, scopes: scopes)
    }

    // MARK: - 계정 연결 (Supabase "Allow manual linking" 필요)

    func identity(for provider: String) -> UserIdentity? { identities.first { $0.provider == provider } }

    func linkGoogle() async throws { try await link(.google) }
    func linkKakao() async throws { try await link(.kakao, scopes: Self.kakaoScopes) }

    func linkApple(idToken: String, rawNonce: String) async throws {
        try await supabase.auth.linkIdentityWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: rawNonce)
        )
        await refreshIdentities()
    }

    /// 마지막 하나는 서버가 거부한다 — 화면에서도 2개 이상일 때만 해제 버튼을 보여줄 것
    func unlink(_ identity: UserIdentity) async throws {
        try await supabase.auth.unlinkIdentity(identity)
        await refreshIdentities()
    }

    func refreshIdentities() async {
        if let fresh = try? await supabase.auth.userIdentities() { identities = fresh }
    }

    private func link(_ provider: Provider, scopes: String? = nil) async throws {
        try await supabase.auth.linkIdentity(provider: provider, scopes: scopes, redirectTo: Self.redirectURL)
        await refreshIdentities()
    }

    /// Safari에서 돌아오는 계정 연결 콜백은 로그인용 ASWebAuthenticationSession과 달리 앱이 직접 교환해야 한다.
    func handleOpenURL(_ url: URL) {
        guard url.scheme == Self.redirectURL.scheme, url.host == Self.redirectURL.host else { return }
        Task { [weak self] in
            do {
                let session = try await supabase.auth.session(from: url)
                guard let self else { return }
                self.session = session
                await self.refreshIdentities()
            } catch {
                Self.log.error("인증 콜백 처리 실패: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - 로그아웃 / 탈퇴

    func signOut() async throws {
        // 데모는 서버 세션이 없다 — 상태만 비우면 AppRouter 가 로그인 화면으로 돌려보낸다
        if isDemo { exitDemo(); return }
        // 왜: SDK는 로컬 세션을 먼저 지운 뒤 네트워크 오류를 던질 수 있어, 캐시 정리는 defer로 보장한다.
        defer { Profile.clearLocalCache() }
        try await supabase.auth.signOut()
    }

    /// 1) 아바타 파일 삭제(Storage API — DB 함수에서 storage.objects 직접 삭제는 Supabase가 막음)
    /// 2) RPC delete_own_account()가 auth.users 행 삭제 → profiles/runs/user_badges cascade
    /// 3) 로컬 세션·캐시 정리 (서버 signOut은 사용자가 이미 없어 실패하므로 .local)
    func deleteAccount() async throws {
        let id = userID
        // 데모는 서버 계정이 없어 RPC 가 실패한다. 심사자는 계정 삭제가 동작하는지 확인하므로
        // (지침 5.1.1(v)) 여기서 조용히 끝내지 않고 로컬 데이터를 실제로 지워 같은 결과를 보인다.
        if isDemo {
            if let id {
                BadgeStore.reset(for: id)
                TrainingStore.reset(for: id)
            }
            exitDemo()
            didDeleteAccount = true
            return
        }
        if let id {
            // 공개 버킷이라 남으면 URL 아는 사람에게 계속 노출된다 → 실패는 남겨서 추적 가능하게
            do {
                try await ProfileService.removeAvatar(userID: id)
            } catch {
                Self.log.error("탈퇴 시 아바타 삭제 실패: \(error.localizedDescription, privacy: .public)")
            }
        }
        try await supabase.rpc("delete_own_account").execute()
        // 계정 삭제는 이미 확정됐다. SDK 로그아웃의 후속 네트워크 실패가 로컬 정리를 막아서는 안 된다.
        try? await supabase.auth.signOut(scope: .local)
        Profile.clearLocalCache()
        if let id {
            // 같은 폰에서 새 계정을 만들 때 옛 캐시가 남지 않도록. 계정별 키를 쓰는 저장소는 전부 정리한다.
            BadgeStore.reset(for: id)
            TrainingStore.reset(for: id)
            // 그 계정으로 다시 로그인할 일이 없어 deleteRemote 가 영영 안 돌고 목록만 쌓인다
            SyncService.pendingDeletes.removeAll { $0.ownerID == id }
        }
        didDeleteAccount = true
    }
}
