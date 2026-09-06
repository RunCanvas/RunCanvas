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
    @AppStorage(VoiceCoach.Keys.enabled) private var voiceGuideEnabled = true

    // 런꾸 설정 — 빈 값이면 "배경에 맞춤"
    @AppStorage(CanvasTheme.storageKey) private var stickerColorHex = ""

    // 앱 설정
    @AppStorage("isNotificationEnabled") private var isNotificationEnabled: Bool = true
    @AppStorage("distanceUnit") private var distanceUnit: String = "km"

    @State private var targetDistanceText = ""
    @State private var weeklyTargetDistanceText = ""
    @State private var isLinking = false
    @State private var appleAuthorizer = AppleAuthorizer()
    @State private var linkMessage: String?
    @State private var isConfirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Group {
                    profileSection
                    runningSection
                    canvasSection
                    appSection
                    linkedAccountsSection
                    accountSection
                    versionFooter
                }
                .listRowBackground(Color.card)
            }
            .listStyle(.insetGrouped)
            .appListTone()
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
                if let v = Double(text), Self.isValidTarget(v) { targetDistance = v }
            }
            .onChange(of: weeklyTargetDistanceText) { _, text in
                if let v = Double(text), Self.isValidTarget(v) { weeklyTargetDistance = v }
            }
            .alert("회원 탈퇴", isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(deleteErrorMessage ?? "")
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
            NavigationLink {
                VoiceSettingsView()
            } label: {
                LabeledContent("음성 안내") {
                    Text(voiceGuideEnabled ? "켬" : "끔")
                }
            }
        } header: {
            Text("러닝 설정")
        } footer: {
            Text("목표는 홈과 기록 화면의 진행률에 쓰여요. 음성 안내는 달리는 동안 거리·시간·페이스를 읽어줘요.")
        }
    }

    // MARK: - 런꾸 설정

    /// 기록 스티커의 기본 색. 편집기에서 하나씩 칠하지 않아도 되게 여기서 미리 정해 둔다.
    private var canvasSection: some View {
        Section {
            Picker("기록 색상", selection: $stickerColorHex) {
                Text("배경에 맞춤").tag("")
                ForEach(CanvasTheme.presets) { preset in
                    Text(preset.name).tag(preset.hex)
                }
                if isCustomStickerColor {
                    Text("직접 고른 색").tag(stickerColorHex)
                }
            }
            ColorPicker("직접 고르기", selection: Binding(
                get: { CanvasTheme.color(hex: stickerColorHex) ?? .white },
                set: { stickerColorHex = CanvasTheme.hex($0) }
            ), supportsOpacity: false)
        } header: {
            Text("런꾸 설정")
        } footer: {
            Text("새로 꾸밀 때 기록 스티커가 이 색으로 시작해요. 배경과 밝기가 비슷해 글씨가 묻히는 경우에는 그 배경에 맞는 색으로 자동으로 바뀌어요.")
        }
    }

    /// 프리셋에 없는 색을 직접 골랐으면 목록에도 그 값을 넣어 준다 (없으면 Picker 가 빈칸이 된다)
    private var isCustomStickerColor: Bool {
        !stickerColorHex.isEmpty && !CanvasTheme.presets.contains { $0.hex == stickerColorHex }
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
                    if isDeleting {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .foregroundStyle(.secondary)
            .disabled(isDeleting)
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

    /// 서버를 **먼저** 지운다 — 반대 순서면 RPC 가 실패했을 때(오프라인·서버 오류) 계정은 살아있는데
    /// 아직 업로드되지 않은 기록만 사라져 영구 손실이 된다.
    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            let id = auth.userID
            try await auth.deleteAccount()
            if let id {   // 서버 삭제가 확정된 뒤에만 로컬 정리 (서버는 RPC 가 cascade)
                let runs = (try? context.fetch(FetchDescriptor<Run>(predicate: #Predicate { $0.ownerID == id }))) ?? []
                runs.compactMap(\.decoratedImageFilename).forEach(CanvasStorage.delete)   // 런꾸 이미지도 같이
                runs.forEach(context.delete)
                try? context.save()
            }
        } catch {
            deleteErrorMessage = "회원 탈퇴에 실패했어요. 네트워크를 확인한 뒤 다시 시도해 주세요."
        }
    }

    /// 숫자 키패드로 아주 큰 수(1e20 등)를 넣을 수 있어 상한을 둔다.
    /// 상한이 없으면 `Int(value)` 가 Int.max 를 넘어 런타임 트랩 → 설정 탭이 영구히 안 열린다.
    private static let maxTargetKm = 1_000.0
    private static func isValidTarget(_ v: Double) -> Bool { v > 0 && v <= maxTargetKm }

    private func formatted(_ value: Double) -> String {
        // %.0f 는 트랩이 없다 (String(Int(value)) 는 범위를 넘으면 크래시)
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

#Preview {
    SettingsView()
        .environment(AuthService())
}
