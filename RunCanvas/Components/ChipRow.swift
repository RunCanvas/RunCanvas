import SwiftUI

/// 가로로 스크롤되는 카테고리 칩 한 줄. 마라톤 일정·공유 코스가 같은 걸 쓴다.
/// 고른 칩은 반전(검정 바탕)이라 색을 쓰지 않고도 선택이 드러난다 — 앱 전체 흑백 톤 유지.
struct ChipRow: View {
    let titles: [String]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(titles, id: \.self) { title in
                    let isOn = title == selected
                    Button { onSelect(title) } label: {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 6)
                            .background(isOn ? Color.primary : Color.card, in: Capsule())
                            .foregroundStyle(isOn ? Color(.systemBackground) : .primary)
                            // 알약 모양은 그대로 두고, 손가락이 닿는 영역만 44pt로 넓힌다.
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

/// 앱의 보조 액션 버튼. 주요 액션과 경쟁하지 않도록 회색 카드 톤을 쓴다.
struct SecondaryButton: View {
    let title: String
    let systemImage: String
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SecondaryButtonLabel(title: title, systemImage: systemImage, isLoading: isLoading)
        }
        .buttonStyle(.plain)
    }
}

/// PhotosPicker·ShareLink처럼 Button이 아닌 컨트롤도 같은 보조 버튼 모양을 쓸 수 있게 라벨을 분리한다.
struct SecondaryButtonLabel: View {
    let title: String
    let systemImage: String
    var isLoading = false

    var body: some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(.headline)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, minHeight: 52)
        .padding(.horizontal, 16)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
