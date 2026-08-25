import Foundation
import Observation
import Supabase

/// Supabase Auth 세션 상태. 구글·카카오는 Supabase OAuth(웹) 플로우로 처리한다 — 네이티브 SDK 없음.
@MainActor
@Observable
final class AuthService {
    private(set) var session: Session?

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

    /// 카카오 이메일(account_email) 동의항목은 비즈 앱 전환 후에만 열리므로 요청 scope에서 뺀다.
    /// 비즈 앱 전환 뒤엔 "account_email"을 추가하고 Supabase Kakao "Allow users without an email"을 끈다.
    func signInWithKakao() async throws { try await signIn(.kakao, scopes: "profile_nickname profile_image") }

    func signOut() async throws {
        try await supabase.auth.signOut()
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
