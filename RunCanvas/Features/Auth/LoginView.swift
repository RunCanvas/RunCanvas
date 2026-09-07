//
//  LoginView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/24/26.
//

import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(AuthService.self) private var auth
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var auth = auth
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "figure.run")
                    .font(.system(size: 45))

                Text("RunCanvas")
                    .font(.largeTitle.bold())
            }

            Spacer()

            VStack(spacing: 12) {
                AppleSignInButton(
                    onToken: { idToken, nonce in signIn { try await auth.signInWithApple(idToken: idToken, rawNonce: nonce) } },
                    onError: { errorMessage = $0 }
                )
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
            .opacity(isBusy ? 0.3 : 1)   // PrimaryButton은 배경을 직접 칠해 disabled여도 안 흐려진다 — 프로필 화면과 같은 처리

            if isBusy {
                ProgressView("로그인 중…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

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
}

#Preview {
    LoginView()
        .environment(AuthService())
}
