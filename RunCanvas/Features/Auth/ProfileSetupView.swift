import SwiftUI

/// 첫 로그인 후 한 번: 닉네임·키·체중(칼로리 계산용) → profiles 행 생성
struct ProfileSetupView: View {
    @Environment(AuthService.self) private var auth
    let onDone: () -> Void

    @State private var nickname = ""
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var trimmedNickname: String { nickname.trimmingCharacters(in: .whitespaces) }
    private var height: Double? { Double(heightText).flatMap { $0 > 0 ? $0 : nil } }
    private var weight: Double? { Double(weightText).flatMap { $0 > 0 ? $0 : nil } }
    private var canSave: Bool { !trimmedNickname.isEmpty && height != nil && weight != nil && !isSaving }

    var body: some View {
        VStack(spacing: 24) {
            Text("프로필 설정")
                .font(.system(size: 30, weight: .bold))
                .padding(.top, 40)

            Text("러닝 기록에 쓸 닉네임과 칼로리 계산에 필요한 키·체중을 알려주세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                TextField("닉네임", text: $nickname)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 12) {
                    TextField("키 (cm)", text: $heightText)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                    TextField("체중 (kg)", text: $weightText)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            PrimaryButton(title: isSaving ? "저장 중…" : "시작하기") {
                Task { await save() }
            }
            .disabled(!canSave)

            Spacer()
        }
        .padding(.horizontal, 24)
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
            errorMessage = "저장에 실패했어요. 네트워크를 확인해 주세요."
        }
    }
}

#Preview {
    ProfileSetupView {}
        .environment(AuthService())
}
