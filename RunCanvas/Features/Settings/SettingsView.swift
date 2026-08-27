import SwiftUI
import AuthenticationServices

/// 앱이 어떻게 동작하나: 상단 프로필 카드(→ 프로필 편집) + 러닝·앱 설정 + 연결된 계정 + 계정.
/// 토글·값은 즉시 저장된다(저장 버튼 없음).
struct SettingsView: View {
    @Environment(AuthService.self) private var auth

    @AppStorage("userNickname") private var userNickname: String = ""
    @AppStorage("avatarURL") private var avatarURL: String = ""

    // 러닝 설정
    @AppStorage("targetDistance") private var targetDistance: Double = 5.0
    @AppStorage("weeklyTargetDistance") private var weeklyTargetDistance: Double = 20.0

    // 앱 설정
    @AppStorage("isNotificationEnabled") private var isNotificationEnabled: Bool = true
    @AppStorage("distanceUnit") private var distanceUnit: String = "km"

    @State private var targetDistanceText = ""
    @State private var weeklyTargetDistanceText = ""
    @State private var isLinking = false
    @State private var appleAuthorizer = AppleAuthorizer()
    @State private var statusMessage: String?
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    profileCard
                    runningSettingSection
                    appSettingSection
                    linkedAccountsSection
                    accountSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .dismissKeyboardOnTap()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") { hideKeyboard() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                targetDistanceText = String(format: "%.1f", targetDistance)
                weeklyTargetDistanceText = String(format: "%.1f", weeklyTargetDistance)
                Task { await auth.refreshIdentities() }
            }
            // 값은 입력 즉시 저장 (0 이하·숫자 아님은 무시)
            .onChange(of: targetDistanceText) { _, text in
                if let v = Double(text), v > 0 { targetDistance = v }
            }
            .onChange(of: weeklyTargetDistanceText) { _, text in
                if let v = Double(text), v > 0 { weeklyTargetDistance = v }
            }
        }
    }

    // MARK: - 프로필 카드 → 프로필 편집

    private var profileCard: some View {
        NavigationLink {
            ProfileEditView()
        } label: {
            HStack(spacing: 14) {
                AvatarView(urlString: avatarURL, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(userNickname.isEmpty ? "러너" : userNickname)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("프로필 편집")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - 러닝 설정

    private var runningSettingSection: some View {
        ProfileSection(title: "러닝 설정") {
            VStack(spacing: 0) {
                ProfileTextFieldRow(title: "1회 목표 거리", text: $targetDistanceText, unit: "km", keyboardType: .decimalPad)
                Divider()
                ProfileTextFieldRow(title: "주간 목표 거리", text: $weeklyTargetDistanceText, unit: "km", keyboardType: .decimalPad)
            }
        }
    }

    // MARK: - 앱 설정

    private var appSettingSection: some View {
        ProfileSection(title: "앱 설정") {
            VStack(spacing: 0) {
                HStack {
                    Text("알림")
                    Spacer()
                    Toggle("", isOn: $isNotificationEnabled)
                        .labelsHidden()
                }
                .padding(.vertical, 14)

                Divider()

                HStack {
                    Text("거리 단위")
                    Spacer()
                    Picker("", selection: $distanceUnit) {
                        Text("km").tag("km")
                        Text("mile").tag("mile")
                    }
                    .pickerStyle(.menu)
                }
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: - 연결된 계정

    /// 다른 로그인 방법을 같은 계정에 붙인다 → 어느 쪽으로 로그인해도 기록이 한 계정에 모임.
    /// Apple "이메일 가리기"로 생기는 중복 가입을 막는 유일한 방법.
    private var linkedAccountsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProfileSection(title: "연결된 계정") {
                VStack(spacing: 0) {
                    linkedRow(name: "Apple", provider: "apple") {
                        linkButton(systemImage: "apple.logo") {
                            let (idToken, nonce) = try await appleAuthorizer.authorize()
                            try await auth.linkApple(idToken: idToken, rawNonce: nonce)
                        }
                    }
                    Divider()
                    linkedRow(name: "Google", provider: "google") {
                        linkButton { try await auth.linkGoogle() }
                    }
                    Divider()
                    linkedRow(name: "카카오", provider: "kakao") {
                        linkButton { try await auth.linkKakao() }
                    }
                }
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private func linkedRow<Action: View>(name: String, provider: String, @ViewBuilder linkAction: () -> Action) -> some View {
        HStack {
            Text(name)
            Spacer()
            if let identity = auth.identity(for: provider) {
                Text("연결됨")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if auth.identities.count > 1 {   // 마지막 하나는 해제 불가
                    Button("해제") { link { try await auth.unlink(identity) } }
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(.leading, 12)
                }
            } else {
                linkAction()
            }
        }
        .padding(.vertical, 12)
        .disabled(isLinking)
    }

    private func linkButton(systemImage: String? = nil, _ action: @escaping @MainActor () async throws -> Void) -> some View {
        Button { link(action) } label: {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage).font(.caption) }
                Text("연결")
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.black)
        .foregroundStyle(.white)
        .clipShape(Capsule())
    }

    private func link(_ action: @escaping @MainActor () async throws -> Void) {
        isLinking = true
        statusMessage = nil
        Task {
            defer { isLinking = false }
            do {
                try await action()
                statusMessage = "계정 연결을 변경했어요."
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                // 사용자가 창을 닫음
            } catch let error as ASAuthorizationError where error.code == .canceled {
                // Apple 시트 취소
            } catch {
                statusMessage = "연결하지 못했어요. 이미 다른 계정에 연결된 로그인 방법이면 그 계정으로 로그인해 주세요."
            }
        }
    }

    // MARK: - 계정

    private var accountSection: some View {
        ProfileSection(title: "계정") {
            VStack(spacing: 0) {
                Button {
                    Task { try? await auth.signOut() }   // AppRouter가 세션 변화를 보고 로그인 화면으로
                } label: {
                    HStack {
                        Text("로그아웃")
                        Spacer()
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.subheadline)
                    }
                    .contentShape(Rectangle())
                }
                .foregroundStyle(.red)
                .padding(.vertical, 14)

                Divider()

                Button {
                    isConfirmingDelete = true
                } label: {
                    HStack {
                        Text("회원 탈퇴")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 14)
                .confirmationDialog("회원 탈퇴할까요?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("탈퇴하기", role: .destructive) { Task { await deleteAccount() } }
                    Button("취소", role: .cancel) {}
                } message: {
                    Text("프로필과 러닝 기록이 모두 삭제되며 되돌릴 수 없습니다.")
                }
            }
        }
    }

    private func deleteAccount() async {
        do {
            try await auth.deleteAccount()   // 성공하면 AppRouter가 세션 변화를 보고 로그인 화면으로
        } catch {
            statusMessage = "회원 탈퇴에 실패했어요. 네트워크를 확인해 주세요."
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthService())
}
