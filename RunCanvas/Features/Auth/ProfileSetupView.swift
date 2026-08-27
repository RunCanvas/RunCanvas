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
    private var height: Double? { Double(heightText).flatMap { $0 > 0 ? $0 : nil } }
    private var weight: Double? { Double(weightText).flatMap { $0 > 0 ? $0 : nil } }
    private var canSave: Bool { !trimmedNickname.isEmpty && height != nil && weight != nil && !isSaving }

    // 입력한 뒤에만 보여주는 필드별 안내 (비어 있을 땐 버튼 비활성으로만)
    private var nicknameHint: String? {
        nickname.isEmpty || !trimmedNickname.isEmpty ? nil : "공백만으로는 쓸 수 없어요."
    }
    private var heightHint: String? {
        heightText.isEmpty || height != nil ? nil : "0보다 큰 숫자로 입력해 주세요."
    }
    private var weightHint: String? {
        weightText.isEmpty || weight != nil ? nil : "0보다 큰 숫자로 입력해 주세요."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("프로필 설정")
                        .font(.system(size: 28, weight: .bold))
                    Text("기록과 칼로리 계산에 쓰여요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                VStack(spacing: 0) {
                    SetupRow(title: "닉네임", text: $nickname, placeholder: "입력해 주세요", hint: nicknameHint)
                        .focused($focus, equals: .nickname)
                        .submitLabel(.next)
                        .onSubmit { focus = .height }
                    Divider()
                    SetupRow(title: "키", text: $heightText, placeholder: "0", unit: "cm", keyboard: .decimalPad, hint: heightHint)
                        .focused($focus, equals: .height)
                    Divider()
                    SetupRow(title: "체중", text: $weightText, placeholder: "0", unit: "kg", keyboard: .decimalPad, hint: weightHint)
                        .focused($focus, equals: .weight)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
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
            .opacity(canSave ? 1 : 0.3)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.background)
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

/// 라벨 · 입력 · 단위 한 줄. 잘못 입력했을 때만 아래에 안내.
private struct SetupRow: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var unit: String = ""
    var keyboard: UIKeyboardType = .default
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField(placeholder, text: $text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
                    .font(.body.weight(.medium))
                if !unit.isEmpty {
                    Text(unit)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .leading)
                }
            }
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 16)
    }
}

#Preview {
    ProfileSetupView {}
        .environment(AuthService())
}
