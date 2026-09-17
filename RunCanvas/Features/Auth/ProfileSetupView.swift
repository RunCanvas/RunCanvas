import SwiftUI

/// 첫 로그인 후 한 번: 닉네임·키·체중(칼로리 계산용) → profiles 행 생성
struct ProfileSetupView: View {
    @Environment(AuthService.self) private var auth
    let onDone: () -> Void

    private enum Field: Hashable { case nickname, height, weight }

    @State private var nickname = ""
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private var trimmedNickname: String { nickname.trimmingCharacters(in: .whitespaces) }
    private var height: Double? { ProfileMeasurement.height(from: heightText) }
    private var weight: Double? { ProfileMeasurement.weight(from: weightText) }
    private var canSave: Bool { !trimmedNickname.isEmpty && height != nil && weight != nil && !isSaving }

    // 입력한 뒤에만 보여주는 필드별 안내 (비어 있을 땐 버튼 비활성으로만)
    private var nicknameHint: String? {
        nickname.isEmpty || !trimmedNickname.isEmpty ? nil : "공백만으로는 쓸 수 없어요."
    }
    private var heightHint: String? {
        heightText.isEmpty || height != nil ? nil : "키는 1~\(Int(ProfileMeasurement.maxHeightCm))cm 사이 숫자로 입력해 주세요."
    }
    private var weightHint: String? {
        weightText.isEmpty || weight != nil ? nil : "체중은 1~\(Int(ProfileMeasurement.maxWeightKg))kg 사이 숫자로 입력해 주세요."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("프로필 설정")
                    .font(.largeTitle.bold())
                Text("기록과 칼로리 계산에 쓰여요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            List {
                Section {
                    LabeledContent("닉네임") {
                        TextField("입력해 주세요", text: $nickname)
                            .focused($focus, equals: .nickname)
                            .submitLabel(.next)
                            .onSubmit { focus = .height }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    numberRow("키", text: $heightText, unit: "cm", field: .height)
                    numberRow("체중", text: $weightText, unit: "kg", field: .weight)
                } header: {
                    Text("기본 정보")
                } footer: {
                    if let hint = nicknameHint ?? heightHint ?? weightHint {
                        Text(hint).foregroundStyle(.red)
                    } else {
                        Text("키와 체중은 칼로리 계산에 쓰여요.")
                    }
                }
                .listRowBackground(Color.card)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .appListTone()
            .contentShape(Rectangle())
            .dismissKeyboardOnTap()
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top) {
            // 다른 방법으로 로그인하려는 사람을 위한 뒤로가기 = 로그아웃
            HStack {
                Button {
                    Task { try? await auth.signOut() }
                } label: {
                    Label("로그인으로", systemImage: "chevron.left")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.background)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: isSaving ? "저장 중…" : "시작하기") {
                focus = nil
                Task { await save() }
            }
            .disabled(!canSave)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(focus == .weight ? "완료" : "다음") {
                    switch focus {
                    case .nickname: focus = .height
                    case .height: focus = .weight
                    default: focus = nil
                    }
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear { focus = .nickname }
    }

    private func numberRow(_ title: String, text: Binding<String>, unit: String, field: Field) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("0", text: text)
                    .focused($focus, equals: field)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func save() async {
        guard let id = auth.userID else { return }
        isSaving = true
        defer { isSaving = false }
        let profile = Profile(id: id, nickname: trimmedNickname, weightKg: weight, heightCm: height, avatarURL: nil)
        do {
            try await ProfileService.upsert(profile)
            profile.cacheLocally()
            onDone()
        } catch {
            errorMessage = "저장하지 못했어요. 네트워크를 확인하고 다시 눌러 주세요."
        }
    }
}

#Preview {
    ProfileSetupView {}
        .environment(AuthService())
}
