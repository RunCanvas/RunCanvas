//
//  LoginView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/24/26.
//

import SwiftUI
import AuthenticationServices
import CryptoKit

struct LoginView: View {
    @Environment(AuthService.self) private var auth
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var appleNonce = ""

    var body: some View {
        @Bindable var auth = auth
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "figure.run")
                    .font(.system(size: 45))

                Text("RunCanvas")
                    .font(.system(size: 30, weight: .bold))
            }

            Spacer()

            VStack(spacing: 12) {
                SignInWithAppleButton(.continue) { request in
                    appleNonce = Self.randomNonce()
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = Self.sha256(appleNonce)
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                PrimaryButton(title: "Google로 계속하기", systemImage: "g.circle") {
                    signIn { try await auth.signInWithGoogle() }
                }
                PrimaryButton(title: "카카오로 계속하기", systemImage: "message.fill") {
                    signIn { try await auth.signInWithKakao() }
                }
            }
            .disabled(isBusy)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
                .frame(height: 40)
        }
        .padding(.horizontal, 24)
        .alert("회원 탈퇴가 완료되었습니다", isPresented: $auth.didDeleteAccount) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("계정과 러닝 기록이 모두 삭제되었습니다. 그동안 이용해 주셔서 감사합니다.")
        }
    }

    private func signIn(_ action: @escaping @MainActor () async throws -> Void) {
        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                try await action()
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                // 사용자가 창을 닫음 — 에러 아님
            } catch {
                errorMessage = "로그인에 실패했어요. 다시 시도해 주세요."
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Apple 로그인 정보를 읽지 못했어요. 다시 시도해 주세요."
                return
            }
            let nonce = appleNonce
            signIn { try await auth.signInWithApple(idToken: idToken, rawNonce: nonce) }
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            errorMessage = "Apple 로그인에 실패했어요. 다시 시도해 주세요."
        }
    }

    // MARK: - Apple nonce (재전송 공격 방지: 요청엔 해시, 검증엔 원본)

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

#Preview {
    LoginView()
        .environment(AuthService())
}
