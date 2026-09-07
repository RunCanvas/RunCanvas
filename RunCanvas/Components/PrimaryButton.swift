import SwiftUI

/// 주요 액션 버튼. 탭 안(레벨 있음)에선 레벨 컬러, 로그인처럼 레벨 없는 곳은 흑백.
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PrimaryButtonLabel(title: title, systemImage: systemImage)
        }
    }
}

/// NavigationLink도 주요 액션 모양을 공유할 수 있게 라벨만 분리한다.
struct PrimaryButtonLabel: View {
    let title: String
    var systemImage: String? = nil
    @Environment(\.levelTier) private var tier

    var body: some View {
        HStack {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.headline)
        .foregroundStyle(tier?.onAccent ?? Color(.systemBackground))
        .frame(maxWidth: .infinity)
        .padding()
        .background(tier?.accent ?? Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
