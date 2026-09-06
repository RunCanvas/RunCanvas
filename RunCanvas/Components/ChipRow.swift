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
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 20)
        }
    }
}
