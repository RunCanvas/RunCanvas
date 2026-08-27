import Foundation
import Observation
import Supabase

/// Supabase Auth 세션 상태. 구글·카카오는 Supabase OAuth(웹) 플로우, Apple은 네이티브 id_token — 외부 SDK 없음.
@MainActor
@Observable
final class AuthService {
    private(set) var session: Session?
    /// 현재 계정에 연결된 로그인 방법들 (provider: "apple" / "google" / "kakao")
    private(set) var identities: [UserIdentity] = []
    /// 탈퇴 직후 로그인 화면이 안내 알럿을 띄우기 위한 1회성 플래그 (알럿이 닫히며 false로 돌아감)
    var didDeleteAccount = false

    #if DEBUG
    /// UI 테스트 전용: 런치 인자 `-uiTestSkipLogin`이면 AppRouter가 고정 계정으로 세팅한다 (릴리즈 빌드엔 없음)
    var debugUserID: UUID?
    var userID: UUID? { debugUserID ?? session?.user.id }
    var isSignedIn: Bool { debugUserID != nil || session != nil }
    #else
    var userID: UUID? { session?.user.id }
    var isSignedIn: Bool { session != nil }
    #endif

    private static let redirectURL = URL(string: "runcanvas://auth-callback")!
    /// 카카오 콘솔 동의항목과 정확히 일치해야 한다(불일치 시 invalid_scope). 이메일은 비즈 앱 전환 후 추가됨.
    private static let kakaoScopes = "profile_nickname profile_image account_email"

    init() {
        session = supabase.auth.currentSession
        identities = session?.user.identities ?? []
        Task { [weak self] in
            for await (_, session) in supabase.auth.authStateChanges {
                self?.session = session
                self?.identities = session?.user.identities ?? []
            }
        }
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

    func isLinked(_ provider: String) -> Bool { identities.contains { $0.provider == provider } }
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

    // MARK: - 로그아웃 / 탈퇴

    func signOut() async throws {
        try await supabase.auth.signOut()
    }

    /// 1) 아바타 파일 삭제(Storage API — DB 함수에서 storage.objects 직접 삭제는 Supabase가 막음)
    /// 2) RPC delete_own_account()가 auth.users 행 삭제 → profiles/runs/user_badges cascade
    /// 3) 로컬 세션·캐시 정리 (서버 signOut은 사용자가 이미 없어 실패하므로 .local)
    func deleteAccount() async throws {
        let id = userID
        if let id {
            _ = try? await supabase.storage.from("avatars").remove(paths: ["\(id.uuidString.lowercased())/avatar.jpg"])
        }
        try await supabase.rpc("delete_own_account").execute()
        try await supabase.auth.signOut(scope: .local)
        Profile.clearLocalCache()
        if let id { BadgeStore.reset(for: id) }   // 같은 폰에서 새 계정을 만들 때 옛 뱃지·챌린지 캐시가 남지 않도록
        didDeleteAccount = true
    }
}
