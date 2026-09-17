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
    @State private var isRemovingAvatar = false
    @State private var isSaving = false
    @State private var statusMessage: String?

    private var trimmedNickname: String { nicknameText.trimmingCharacters(in: .whitespaces) }
    private var height: Double? { ProfileMeasurement.height(from: heightText) }
    private var weight: Double? { ProfileMeasurement.weight(from: weightText) }
    private var canSave: Bool {
        !trimmedNickname.isEmpty && height != nil && weight != nil
            && !isSaving && !isUploadingAvatar && !isRemovingAvatar
    }

    /// 입력한 뒤에만 보여주는 범위 안내 (비어 있을 땐 버튼 비활성으로만)
    private var rangeHint: String? {
        if !heightText.isEmpty && height == nil { return "키는 1~\(Int(ProfileMeasurement.maxHeightCm))cm 사이 숫자로 입력해 주세요." }
        if !weightText.isEmpty && weight == nil { return "체중은 1~\(Int(ProfileMeasurement.maxWeightKg))kg 사이 숫자로 입력해 주세요." }
        return nil
    }

    var body: some View {
        List {
            Group {
                Section {
                    avatarPicker
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                Section {
                    LabeledContent("닉네임") {
                        TextField("입력해 주세요", text: $nicknameText)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(.primary)
                    }
                    numberRow("키", text: $heightText, unit: "cm")
                    numberRow("체중", text: $weightText, unit: "kg")
                } header: {
                    Text("기본 정보")
                } footer: {
                    Text(rangeHint ?? statusMessage ?? "키와 체중은 칼로리 계산에 쓰여요.")
                }
            }
            .listRowBackground(Color.card)
        }
        .listStyle(.insetGrouped)
        .appListTone()
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: isSaving ? "저장 중…" : "저장") {
                hideKeyboard()
                Task { await save() }
            }
            .disabled(!canSave)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))   // ProfileSetupView 와 같은 불투명 시스템 배경
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
            weightText = formatted(userWeight)
            heightText = formatted(userHeight)
        }
        .onChange(of: pickedAvatar) { _, item in
            guard let item, !isUploadingAvatar else { return }   // PhotosPicker가 선택을 두 번 알리는 경우 중복 업로드 방지
            Task { await uploadAvatar(item) }
        }
    }

    private var avatarPicker: some View {
        VStack(spacing: 12) {
            // `.any(of: [.images, .not(.livePhotos)])` 는 합집합이라 동영상까지 다 보였다.
            // 라이브포토는 .compatible 인코딩으로 정지 이미지가 오므로 .images 만으로 충분하다.
            PhotosPicker(selection: $pickedAvatar, matching: .images, preferredItemEncoding: .compatible) {
                VStack(spacing: 10) {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarView(urlString: avatarURL, size: 96)
                        Image(systemName: "camera.fill")
                            .font(.caption)
                            .foregroundStyle(Color(.systemBackground))   // 앱의 반전 칩 어휘 — 다크에서도 배지가 보이게
                            .padding(7)
                            .background(Color.primary)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    }
                    Text(isUploadingAvatar ? "업로드 중…" : "사진 변경")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
            .disabled(isUploadingAvatar || isRemovingAvatar)

            if !avatarURL.isEmpty {
                Button("사진 삭제", role: .destructive) {
                    Task { await removeAvatar() }
                }
                .font(.subheadline.weight(.semibold))
                .disabled(isUploadingAvatar || isRemovingAvatar)
            }
        }
        .padding(.bottom, 8)
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

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        userNickname = trimmedNickname
        if let weight { userWeight = weight }
        if let height { userHeight = height }

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
            guard let data = try await withTimeoutValue(seconds: 20, { try await item.loadTransferable(type: Data.self) }),
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

    private func removeAvatar() async {
        guard let id = auth.userID else { return }
        isRemovingAvatar = true
        defer { isRemovingAvatar = false }
        do {
            // 왜: URL만 nil로 바꾸면 공개 버킷의 얼굴 사진 원본은 계속 접근할 수 있다.
            try await ProfileService.removeAvatar(userID: id)
            try await ProfileService.upsert(
                Profile(id: id, nickname: userNickname, weightKg: userWeight, heightCm: userHeight, avatarURL: nil)
            )
            avatarURL = ""
            statusMessage = "프로필 사진을 삭제했어요."
        } catch {
            // 스토리지 삭제 뒤 DB 반영만 실패해도 버튼을 남겨 재시도할 수 있게 로컬 URL은 유지한다.
            statusMessage = "사진을 삭제하지 못했어요. 다시 시도해 주세요."
        }
    }

    private func formatted(_ value: Double) -> String {
        // NumberFormatter는 Int 변환 트랩 없이 현재 숫자 키패드의 소수점과 같은 표기를 만든다.
        ProfileMeasurement.format(value)
    }
}

#Preview {
    NavigationStack {
        ProfileEditView()
    }
    .environment(AuthService())
}
