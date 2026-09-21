import SwiftUI
import PhotosUI
import UIKit

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
    @State private var pendingAvatarJPEG: Data?
    @State private var pendingAvatarImage: UIImage?
    @State private var removesAvatarOnSave = false
    @State private var isLoadingAvatar = false
    @State private var isSaving = false
    @State private var statusMessage: String?

    private var trimmedNickname: String { nicknameText.trimmingCharacters(in: .whitespaces) }
    private var height: Double? { ProfileMeasurement.height(from: heightText) }
    private var weight: Double? { ProfileMeasurement.weight(from: weightText) }
    private var canSave: Bool {
        !trimmedNickname.isEmpty && height != nil && weight != nil
            && !isSaving && !isLoadingAvatar
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
            guard let item, !isLoadingAvatar else { return }   // PhotosPicker가 선택을 두 번 알리는 경우 중복 로드 방지
            Task { await prepareAvatar(item) }
        }
    }

    private var avatarPicker: some View {
        VStack(spacing: 12) {
            // `.any(of: [.images, .not(.livePhotos)])` 는 합집합이라 동영상까지 다 보였다.
            // 라이브포토는 .compatible 인코딩으로 정지 이미지가 오므로 .images 만으로 충분하다.
            PhotosPicker(selection: $pickedAvatar, matching: .images, preferredItemEncoding: .compatible) {
                VStack(spacing: 10) {
                    ZStack(alignment: .bottomTrailing) {
                        avatarPreview
                        Image(systemName: "camera.fill")
                            .font(.caption)
                            .foregroundStyle(Color(.systemBackground))   // 앱의 반전 칩 어휘 — 다크에서도 배지가 보이게
                            .padding(7)
                            .background(Color.primary)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    }
                    Text(isLoadingAvatar ? "사진 준비 중…" : "사진 변경")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
            .disabled(isLoadingAvatar || isSaving)

            if pendingAvatarImage != nil || !avatarURL.isEmpty {
                Button(removesAvatarOnSave ? "사진 삭제 예정" : "사진 삭제", role: .destructive) {
                    pendingAvatarJPEG = nil
                    pendingAvatarImage = nil
                    pickedAvatar = nil
                    removesAvatarOnSave = true
                    statusMessage = "저장을 누르면 프로필 사진을 삭제해요."
                }
                .font(.subheadline.weight(.semibold))
                .disabled(isLoadingAvatar || isSaving || removesAvatarOnSave)
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
        guard let weight, let height else { return }
        // 데모(canSync=false)는 서버 계정이 없다 — 올리려 들면 실패하므로 로컬에만 저장한다
        guard auth.canSync, let id = auth.userID else {
            userNickname = trimmedNickname
            userWeight = weight
            userHeight = height
            dismiss()
            return
        }
        do {
            var savedAvatarURL: String? = avatarURL.isEmpty ? nil : avatarURL
            if let pendingAvatarJPEG {
                savedAvatarURL = try await ProfileService.uploadAvatar(userID: id, jpeg: pendingAvatarJPEG)
            } else if removesAvatarOnSave {
                // 공개 버킷의 원본을 먼저 지워야 URL만 빈 채로 남지 않는다.
                try await ProfileService.removeAvatar(userID: id)
                savedAvatarURL = nil
            }

            try await ProfileService.upsert(
                Profile(id: id, nickname: trimmedNickname, weightKg: weight, heightCm: height, avatarURL: savedAvatarURL)
            )

            // 서버 저장이 끝난 뒤에만 홈이 보는 로컬 캐시를 바꿔 '자동 저장'처럼 보이지 않게 한다.
            userNickname = trimmedNickname
            userWeight = weight
            userHeight = height
            avatarURL = savedAvatarURL ?? ""
            dismiss()
        } catch {
            statusMessage = "저장하지 못했어요. 잠시 후 다시 시도해 주세요."
        }
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let pendingAvatarImage {
            Image(uiImage: pendingAvatarImage)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(Circle())
        } else {
            AvatarView(urlString: removesAvatarOnSave ? "" : avatarURL, size: 96)
        }
    }

    /// 사진을 선택해도 서버로 보내지 않고, 화면 미리보기와 저장용 JPEG만 준비한다.
    private func prepareAvatar(_ item: PhotosPickerItem) async {
        isLoadingAvatar = true
        defer { isLoadingAvatar = false }
        do {
            // 시뮬레이터/일부 HEIC에서 loadTransferable이 영영 안 끝나는 경우가 있어 타임아웃을 건다
            guard let data = try await withTimeoutValue(seconds: 20, { try await item.loadTransferable(type: Data.self) }),
                  let image = UIImage(data: data),
                  let thumb = await image.byPreparingThumbnail(ofSize: CGSize(width: 512, height: 512)),
                  let jpeg = thumb.jpegData(compressionQuality: 0.85) else {
                statusMessage = "이미지를 읽을 수 없어요."
                return
            }
            pendingAvatarJPEG = jpeg
            pendingAvatarImage = thumb
            removesAvatarOnSave = false
            statusMessage = "저장을 누르면 프로필 사진을 바꿔요."
        } catch is CancellationError {
            statusMessage = "사진을 불러오지 못했어요. 다른 사진으로 시도해 주세요."
        } catch {
            statusMessage = "사진을 준비하지 못했어요."
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
