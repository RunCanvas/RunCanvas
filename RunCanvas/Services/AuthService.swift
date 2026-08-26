import Foundation
import Observation
import Supabase

/// Supabase Auth 세션 상태. 구글·카카오는 Supabase OAuth(웹) 플로우로 처리한다 — 네이티브 SDK 없음.
@MainActor
@Observable
final class AuthService {
    private(set) var session: Session?
    /// 탈퇴 직후 로그인 화면이 안내 알럿을 띄우기 위한 1회성 플래그 (알럿이 닫히며 false로 돌아감)
    var didDeleteAccount = false

    var userID: UUID? { session?.user.id }
    var isSignedIn: Bool { session != nil }

    init() {
        session = supabase.auth.currentSession
        Task { [weak self] in
            for await (_, session) in supabase.auth.authStateChanges {
                self?.session = session
            }
        }
    }

    func signInWithGoogle() async throws { try await signIn(.google) }

    /// scope는 카카오 콘솔 동의항목과 정확히 일치해야 한다(불일치 시 invalid_scope). 이메일은 비즈 앱 전환 후 추가됨.
    func signInWithKakao() async throws { try await signIn(.kakao, scopes: "profile_nickname profile_image account_email") }

    func signOut() async throws {
        try await supabase.auth.signOut()
    }

    /// 1) 아바타 파일 삭제(Storage API — DB 함수에서 storage.objects 직접 삭제는 Supabase가 막음)
    /// 2) RPC delete_own_account()가 auth.users 행 삭제 → profiles/runs/user_badges cascade
    /// 3) 로컬 세션·캐시 정리 (서버 signOut은 사용자가 이미 없어 실패하므로 .local)
    func deleteAccount() async throws {
        if let id = userID {
            _ = try? await supabase.storage.from("avatars").remove(paths: ["\(id.uuidString.lowercased())/avatar.jpg"])
        }
        try await supabase.rpc("delete_own_account").execute()
        try await supabase.auth.signOut(scope: .local)
        Profile.clearLocalCache()
        didDeleteAccount = true
    }

    private func signIn(_ provider: Provider, scopes: String? = nil) async throws {
        // ASWebAuthenticationSession이 runcanvas:// 콜백을 잡는다 (Info.plist URL 스킴, Supabase Redirect URL 등록됨)
        _ = try await supabase.auth.signInWithOAuth(
            provider: provider,
            redirectTo: URL(string: "runcanvas://auth-callback")!,
            scopes: scopes
        )
    }
}
