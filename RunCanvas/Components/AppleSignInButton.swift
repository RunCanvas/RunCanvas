import SwiftUI
import AuthenticationServices
import CryptoKit

/// Sign in with Apple 버튼(Apple 기본 스타일) + nonce 처리. 성공하면 (identityToken, rawNonce)를 넘긴다.
/// 로그인 화면용. 설정 화면의 "연결"처럼 작은 버튼이 필요하면 AppleAuthorizer를 쓴다.
struct AppleSignInButton: View {
    var label: SignInWithAppleButton.Label = .continue
    let onToken: (_ idToken: String, _ rawNonce: String) -> Void
    var onError: (String) -> Void = { _ in }

    @State private var nonce = ""

    var body: some View {
        SignInWithAppleButton(label) { request in
            nonce = AppleNonce.random()
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleNonce.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let idToken = AppleNonce.idToken(from: authorization) else {
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
}

/// Apple 인증을 버튼 없이 코드로 띄운다 (계정 연결처럼 커스텀 버튼이 필요한 곳). 요청 중엔 객체를 살려둘 것.
@MainActor
final class AppleAuthorizer: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<(idToken: String, rawNonce: String), Error>?
    private var nonce = ""

    func authorize() async throws -> (idToken: String, rawNonce: String) {
        nonce = AppleNonce.random()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleNonce.sha256(nonce)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let idToken = AppleNonce.idToken(from: authorization) {
            continuation?.resume(returning: (idToken, nonce))
        } else {
            continuation?.resume(throwing: ASAuthorizationError(.failed))
        }
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}

/// nonce: 요청엔 sha256(raw)를, Supabase 검증엔 raw를 쓴다(재전송 공격 방지)
enum AppleNonce {
    static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        // 반환값을 버리면 실패 시 bytes 가 전부 0인 채로 남아 nonce 가 "000…0" 고정 문자열이 된다.
        // 사용자에겐 정상 로그인처럼 보이고 재전송 방지라는 존재 이유만 조용히 사라진다.
        guard SecRandomCopyBytes(kSecRandomDefault, length, &bytes) == errSecSuccess else {
            return (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "")
        }
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func idToken(from authorization: ASAuthorization) -> String? {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
