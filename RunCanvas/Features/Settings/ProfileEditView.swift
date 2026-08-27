import SwiftUI
import PhotosUI

/// 내가 누구인가: 사진 · 닉네임 · 키 · 체중. 저장 버튼 하나로 로컬(@AppStorage) + 서버(profiles) 동기화.
struct ProfileEditView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @AppStorage("userNickname") private var userNickname: String = ""
    @AppStorage("userWeight") private var userWeight: Double = 60.0
    @AppStorage("userHeight") private var userHeight: Double = 165.0
    @AppStorage("avatarURL") private var avatarURL: String = ""

    @State private var nicknameText = ""
    @State private var weightText = ""
    @State private var heightText = ""

    @State private var pickedAvatar: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var isSaving = false
    @State private var statusMessage: String?

    private var trimmedNickname: String { nicknameText.trimmingCharacters(in: .whitespaces) }
    private var canSave: Bool {
        !trimmedNickname.isEmpty && (Double(heightText) ?? 0) > 0 && (Double(weightText) ?? 0) > 0 && !isSaving
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                avatarPicker
                    .padding(.top, 8)

                ProfileSection(title: "기본 정보") {
                    VStack(spacing: 0) {
                        ProfileTextFieldRow(title: "닉네임", text: $nicknameText, keyboardType: .default)
                        Divider()
                        ProfileTextFieldRow(title: "키", text: $heightText, unit: "cm", keyboardType: .decimalPad)
                        Divider()
                        ProfileTextFieldRow(title: "체중", text: $weightText, unit: "kg", keyboardType: .decimalPad)
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .dismissKeyboardOnTap()
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: isSaving ? "저장 중…" : "저장") {
                hideKeyboard()
                Task { await save() }
            }
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.3)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("프로필 편집")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") { hideKeyboard() }
                    .fontWeight(.semibold)
            }
        }
        .onAppear {
            nicknameText = userNickname
            weightText = String(format: "%.1f", userWeight)
            heightText = String(format: "%.1f", userHeight)
        }
        .onChange(of: pickedAvatar) { _, item in
            guard let item, !isUploadingAvatar else { return }   // PhotosPicker가 선택을 두 번 알리는 경우 중복 업로드 방지
            Task { await uploadAvatar(item) }
        }
    }

    private var avatarPicker: some View {
        PhotosPicker(selection: $pickedAvatar, matching: .any(of: [.images, .not(.livePhotos)]), preferredItemEncoding: .compatible) {
            VStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(urlString: avatarURL, size: 96)
                    Image(systemName: "camera.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(.black)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.background, lineWidth: 2))
                }
                Text(isUploadingAvatar ? "업로드 중…" : "사진 변경")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isUploadingAvatar)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        userNickname = trimmedNickname
        if let weight = Double(weightText), weight > 0 { userWeight = weight }
        if let height = Double(heightText), height > 0 { userHeight = height }

        guard let id = auth.userID else { dismiss(); return }
        do {
            try await ProfileService.upsert(
                Profile(id: id, nickname: userNickname, weightKg: userWeight, heightCm: userHeight, avatarURL: avatarURL.isEmpty ? nil : avatarURL)
            )
            dismiss()
        } catch {
            statusMessage = "기기에는 저장됐지만 서버 동기화에 실패했어요."
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

#Preview {
    NavigationStack {
        ProfileEditView()
    }
    .environment(AuthService())
}
