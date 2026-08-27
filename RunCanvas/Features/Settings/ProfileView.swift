//
//  ProfileView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/24/26.
//

import SwiftUI
import PhotosUI
import AuthenticationServices

struct ProfileView: View {
    @Environment(AuthService.self) private var auth

    // 저장되는 사용자 정보 (로컬 캐시 — 서버 원본은 Supabase profiles)
    @AppStorage("userNickname") private var userNickname: String = "다은"
    @AppStorage("userWeight") private var userWeight: Double = 60.0
    @AppStorage("userHeight") private var userHeight: Double = 165.0
    @AppStorage("avatarURL") private var avatarURL: String = ""

    // 러닝 설정
    @AppStorage("targetDistance") private var targetDistance: Double = 5.0
    @AppStorage("weeklyTargetDistance") private var weeklyTargetDistance: Double = 20.0

    // 앱 설정
    @AppStorage("isNotificationEnabled") private var isNotificationEnabled: Bool = true
    @AppStorage("distanceUnit") private var distanceUnit: String = "km"

    @State private var nicknameText = ""
    @State private var weightText = ""
    @State private var heightText = ""
    @State private var targetDistanceText = ""
    @State private var weeklyTargetDistanceText = ""

    @State private var pickedAvatar: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var isLinking = false
    @State private var appleAuthorizer = AppleAuthorizer()
    @State private var statusMessage: String?
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // 프로필 정보
                    profileSection

                    // 러닝 설정
                    runningSettingSection

                    // 앱 설정
                    appSettingSection

                    // 연결된 계정
                    linkedAccountsSection

                    // 계정
                    accountSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .dismissKeyboardOnTap()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("프로필")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") { hideKeyboard() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadSavedData()
                Task { await auth.refreshIdentities() }
            }
            .onChange(of: pickedAvatar) { _, item in
                guard let item, !isUploadingAvatar else { return }   // PhotosPicker가 선택을 두 번 알리는 경우 중복 업로드 방지
                Task { await uploadAvatar(item) }
            }
        }
    }

    // MARK: - 프로필 정보

    private var profileSection: some View {
        ProfileSection(title: "기본 정보") {
            VStack(spacing: 0) {

                avatarRow

                Divider()

                ProfileTextFieldRow(
                    title: "닉네임",
                    text: $nicknameText,
                    keyboardType: .default
                )

                Divider()

                ProfileTextFieldRow(
                    title: "체중",
                    text: $weightText,
                    unit: "kg",
                    keyboardType: .decimalPad
                )

                Divider()

                ProfileTextFieldRow(
                    title: "키",
                    text: $heightText,
                    unit: "cm",
                    keyboardType: .decimalPad
                )
            }
        }
    }

    private var avatarRow: some View {
        HStack {
            Text("프로필 사진")

            Spacer()

            PhotosPicker(selection: $pickedAvatar, matching: .any(of: [.images, .not(.livePhotos)]), preferredItemEncoding: .compatible) {
                HStack(spacing: 10) {
                    Text(isUploadingAvatar ? "업로드 중…" : "변경")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 44, height: 44)

                        if let url = URL(string: avatarURL), !avatarURL.isEmpty {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .disabled(isUploadingAvatar)
        }
        .padding(.vertical, 10)
    }

    // MARK: - 러닝 설정

    private var runningSettingSection: some View {
        ProfileSection(title: "러닝 설정") {
            VStack(spacing: 0) {

                ProfileTextFieldRow(
                    title: "1회 목표 거리",
                    text: $targetDistanceText,
                    unit: "km",
                    keyboardType: .decimalPad
                )

                Divider()

                ProfileTextFieldRow(
                    title: "주간 목표 거리",
                    text: $weeklyTargetDistanceText,
                    unit: "km",
                    keyboardType: .decimalPad
                )
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
        VStack(spacing: 12) {

            PrimaryButton(title: "저장") {
                Task { await saveData() }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { try? await auth.signOut() }   // AppRouter가 세션 변화를 보고 로그인 화면으로
            } label: {
                Text("로그아웃")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            .padding(.top, 8)

            Button("계정 삭제") { isConfirmingDelete = true }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .confirmationDialog("계정을 삭제할까요?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("계정 삭제", role: .destructive) { Task { await deleteAccount() } }
                    Button("취소", role: .cancel) {}
                } message: {
                    Text("프로필과 러닝 기록이 모두 삭제되며 되돌릴 수 없습니다.")
                }
        }
    }

    // MARK: - 데이터

    private func loadSavedData() {
        nicknameText = userNickname
        weightText = String(format: "%.1f", userWeight)
        heightText = String(format: "%.1f", userHeight)
        targetDistanceText = String(format: "%.1f", targetDistance)
        weeklyTargetDistanceText = String(format: "%.1f", weeklyTargetDistance)
    }

    /// 로컬(@AppStorage)엔 항상 저장하고, 서버(profiles)엔 닉네임·체중·키·아바타를 동기화한다.
    private func saveData() async {
        if !nicknameText.isEmpty {
            userNickname = nicknameText
        }

        if let weight = Double(weightText), weight > 0 {
            userWeight = weight
        }

        if let height = Double(heightText), height > 0 {
            userHeight = height
        }

        if let target = Double(targetDistanceText), target > 0 {
            targetDistance = target
        }

        if let weeklyTarget = Double(weeklyTargetDistanceText), weeklyTarget > 0 {
            weeklyTargetDistance = weeklyTarget
        }

        guard let id = auth.userID else {
            statusMessage = "저장되었습니다."
            return
        }
        do {
            try await ProfileService.upsert(
                Profile(id: id, nickname: userNickname, weightKg: userWeight, heightCm: userHeight, avatarURL: avatarURL.isEmpty ? nil : avatarURL)
            )
            statusMessage = "저장되었습니다."
        } catch {
            statusMessage = "기기에는 저장됐지만 서버 동기화에 실패했어요."
        }
    }

    private func deleteAccount() async {
        do {
            try await auth.deleteAccount()   // 성공하면 AppRouter가 세션 변화를 보고 로그인 화면으로
        } catch {
            statusMessage = "계정 삭제에 실패했어요. 네트워크를 확인해 주세요."
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        guard let id = auth.userID else { return }
        isUploadingAvatar = true
        defer { isUploadingAvatar = false; pickedAvatar = nil }
        do {
            // 시뮬레이터/일부 HEIC에서 loadTransferable이 영영 안 끝나는 경우가 있어 타임아웃을 건다
            guard let data = try await withTimeout(seconds: 20, { try await item.loadTransferable(type: Data.self) }),
                  let image = UIImage(data: data),
                  let thumb = await image.byPreparingThumbnail(ofSize: CGSize(width: 512, height: 512)),
                  let jpeg = thumb.jpegData(compressionQuality: 0.85) else {
                statusMessage = "이미지를 읽을 수 없어요."
                return
            }
            let url = try await ProfileService.uploadAvatar(userID: id, jpeg: jpeg)
            avatarURL = url
            try await ProfileService.upsert(Profile(id: id, nickname: userNickname, weightKg: userWeight, heightCm: userHeight, avatarURL: url))
            statusMessage = "프로필 사진을 바꿨어요."
        } catch is CancellationError {
            statusMessage = "사진을 불러오지 못했어요. 다른 사진으로 시도해 주세요."
        } catch {
            statusMessage = "사진 업로드에 실패했어요."
        }
    }
}

/// op가 seconds 안에 안 끝나면 CancellationError
private func withTimeout<T: Sendable>(seconds: Double, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await op() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw CancellationError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// MARK: - 프로필 섹션

struct ProfileSection<Content: View>: View {
    let title: String
    let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            VStack {
                content
            }
            .padding(.horizontal, 16)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - 입력 행

struct ProfileTextFieldRow: View {
    let title: String
    @Binding var text: String
    var unit: String = ""
    var keyboardType: UIKeyboardType

    var body: some View {
        HStack {
            Text(title)

            Spacer()

            TextField("", text: $text)
                .keyboardType(keyboardType)
                .multilineTextAlignment(.trailing)
                .frame(width: 120)

            if !unit.isEmpty {
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .leading)
            }
        }
        .padding(.vertical, 14)
    }
}

#Preview {
    ProfileView()
        .environment(AuthService())
}
