import SwiftUI
import SwiftData
import AuthenticationServices

/// 앱이 어떻게 동작하나: 프로필 카드(→ 편집) · 러닝 설정 · 앱 설정 · 연결된 계정 · 계정.
/// iOS 설정 앱과 같은 인셋 그룹 리스트. 값은 즉시 저장된다(저장 버튼 없음).
struct SettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.modelContext) private var context

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
    @State private var linkMessage: String?
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            List {
                profileSection
                runningSection
                appSection
                linkedAccountsSection
                accountSection
                versionFooter
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("설정")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") { hideKeyboard() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                targetDistanceText = formatted(targetDistance)
                weeklyTargetDistanceText = formatted(weeklyTargetDistance)
                Task { await auth.refreshIdentities() }
            }
            // 값은 입력 즉시 저장 (0 이하·숫자 아님은 무시)
            .onChange(of: targetDistanceText) { _, text in
                if let v = Double(text), v > 0 { targetDistance = v }
            }
            .onChange(of: weeklyTargetDistanceText) { _, text in
                if let v = Double(text), v > 0 { weeklyTargetDistance = v }
            }
            .confirmationDialog("회원 탈퇴할까요?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("탈퇴하기", role: .destructive) { Task { await deleteAccount() } }
                Button("취소", role: .cancel) {}
            } message: {
                Text("프로필과 러닝 기록이 모두 삭제되며 되돌릴 수 없습니다.")
            }
        }
    }

    // MARK: - 프로필

    private var profileSection: some View {
        Section {
            NavigationLink {
                ProfileEditView()
            } label: {
                HStack(spacing: 14) {
                    AvatarView(urlString: avatarURL, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(userNickname.isEmpty ? "러너" : userNickname)
                            .font(.title3.weight(.semibold))
                        Text("프로필 편집")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            NavigationLink {
                BadgesView(ownerID: auth.userID)
            } label: {
                Label("레벨과 뱃지", systemImage: "medal")
            }
        }
    }

    // MARK: - 러닝 설정

    private var runningSection: some View {
        Section {
            numberRow("1회 목표 거리", text: $targetDistanceText, unit: "km")
            numberRow("주간 목표 거리", text: $weeklyTargetDistanceText, unit: "km")
        } header: {
            Text("러닝 설정")
        } footer: {
            Text("목표는 홈과 기록 화면의 진행률에 쓰여요.")
        }
    }

    private func numberRow(_ title: String, text: Binding<String>, unit: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.primary)
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 앱 설정

    private var appSection: some View {
        Section("앱 설정") {
            Toggle("알림", isOn: $isNotificationEnabled)
            Picker("거리 단위", selection: $distanceUnit) {
                Text("킬로미터 (km)").tag("km")
                Text("마일 (mi)").tag("mile")
            }
        }
    }

    // MARK: - 연결된 계정

    /// 다른 로그인 방법을 같은 계정에 붙인다 → 어느 쪽으로 로그인해도 기록이 한 계정에 모임.
    /// Apple "이메일 가리기"로 생기는 중복 가입을 막는 유일한 방법.
    private var linkedAccountsSection: some View {
        Section {
            linkedRow(name: "Apple", icon: "apple.logo", provider: "apple") {
                let (idToken, nonce) = try await appleAuthorizer.authorize()
                try await auth.linkApple(idToken: idToken, rawNonce: nonce)
            }
            linkedRow(name: "Google", icon: "g.circle", provider: "google") {
                try await auth.linkGoogle()
            }
            linkedRow(name: "카카오", icon: "message.fill", provider: "kakao") {
                try await auth.linkKakao()
            }
        } header: {
            Text("연결된 계정")
        } footer: {
            Text(linkMessage ?? "연결해 두면 어느 방법으로 로그인해도 같은 계정으로 들어와요.")
        }
    }

    private func linkedRow(name: String, icon: String, provider: String, link action: @escaping @MainActor () async throws -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.primary)
            Text(name)
            Spacer()
            if let identity = auth.identity(for: provider) {
                Text("연결됨")
                    .foregroundStyle(.secondary)
                if auth.identities.count > 1 {   // 마지막 하나는 해제 불가
                    Button("해제") { link { try await auth.unlink(identity) } }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .padding(.leading, 8)
                }
            } else {
                Button("연결") { link(action) }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .fontWeight(.semibold)
            }
        }
        .disabled(isLinking)
    }

    private func link(_ action: @escaping @MainActor () async throws -> Void) {
        isLinking = true
        linkMessage = nil
        Task {
            defer { isLinking = false }
            do {
                try await action()
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                // 사용자가 창을 닫음
            } catch let error as ASAuthorizationError where error.code == .canceled {
                // Apple 시트 취소
            } catch {
                linkMessage = "연결하지 못했어요. 이미 다른 계정에 연결된 로그인 방법이면 그 계정으로 로그인해 주세요."
            }
        }
    }

    // MARK: - 계정

    private var accountSection: some View {
        Section("계정") {
            Button {
                Task { try? await auth.signOut() }   // AppRouter가 세션 변화를 보고 로그인 화면으로
            } label: {
                Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .foregroundStyle(.red)

            Button {
                isConfirmingDelete = true
            } label: {
                HStack {
                    Text("회원 탈퇴")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private var versionFooter: some View {
        Section {
        } footer: {
            let info = Bundle.main.infoDictionary
            let version = info?["CFBundleShortVersionString"] as? String ?? "-"
            let build = info?["CFBundleVersion"] as? String ?? "-"
            Text("RunCanvas \(version) (\(build))")
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }

    private func deleteAccount() async {
        do {
            if let id = auth.userID {   // 이 계정의 로컬 기록 삭제 (서버는 RPC가 cascade)
                try context.delete(model: Run.self, where: #Predicate { $0.ownerID == id })
                try context.save()
            }
            try await auth.deleteAccount()   // 성공하면 AppRouter가 세션 변화를 보고 로그인 화면으로
        } catch {
            linkMessage = "회원 탈퇴에 실패했어요. 네트워크를 확인해 주세요."
        }
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

#Preview {
    SettingsView()
        .environment(AuthService())
}
