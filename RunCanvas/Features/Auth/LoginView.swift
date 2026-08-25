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
                PrimaryButton(title: "Google로 계속하기", systemImage: "g.circle") {
                    signIn { try await auth.signInWithGoogle() }
                }
                PrimaryButton(title: "카카오로 계속하기", systemImage: "message.fill") {
                    signIn { try await auth.signInWithKakao() }
                }
                // Apple 로그인: Supabase Apple 프로바이더(.p8) 설정 후 추가
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
