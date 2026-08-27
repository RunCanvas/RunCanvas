import SwiftUI
import AuthenticationServices
import CryptoKit

/// Sign in with Apple 버튼 + nonce 처리. 성공하면 (identityToken, rawNonce)를 넘긴다 — 로그인·계정 연결 둘 다 이걸로.
/// 요청엔 sha256(rawNonce)를, Supabase 검증엔 rawNonce를 쓴다(재전송 공격 방지).
struct AppleSignInButton: View {
    var label: SignInWithAppleButton.Label = .continue
    let onToken: (_ idToken: String, _ rawNonce: String) -> Void
    var onError: (String) -> Void = { _ in }

    @State private var nonce = ""

    var body: some View {
        SignInWithAppleButton(label) { request in
            nonce = Self.randomNonce()
            request.requestedScopes = [.fullName, .email]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let idToken = String(data: tokenData, encoding: .utf8) else {
                    onError("Apple 로그인 정보를 읽지 못했어요. 다시 시도해 주세요.")
                    return
                }
                onToken(idToken, nonce)
            case .failure(let error):
                if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
                onError("Apple 로그인에 실패했어요. 다시 시도해 주세요.")
            }
        }
        .signInWithAppleButtonStyle(.black)
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
