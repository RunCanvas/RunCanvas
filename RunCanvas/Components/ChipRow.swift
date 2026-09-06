import SwiftUI

/// 가로로 스크롤되는 카테고리 칩 한 줄. 마라톤 일정·공유 코스가 같은 걸 쓴다.
/// 고른 칩은 반전(검정 바탕)이라 색을 쓰지 않고도 선택이 드러난다 — 앱 전체 흑백 톤 유지.
struct ChipRow: View {
    let titles: [String]
    let selected: String
    /// 칩 옆에 붙일 개수(있는 것만). 0이면 눌러도 빈 화면이라는 뜻이라 흐리게 보여준다
    var counts: [String: Int] = [:]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(titles, id: \.self) { title in
                    let isOn = title == selected
                    let count = counts[title]
                    Button { onSelect(title) } label: {
                        HStack(spacing: 4) {
                            Text(title)
                            if let count {
                                Text("\(count)")
                                    .monospacedDigit()
                                    .foregroundStyle(isOn ? Color(.systemBackground).opacity(0.7) : .secondary)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(isOn ? Color.primary : Color.card, in: Capsule())
                        .foregroundStyle(isOn ? Color(.systemBackground) : .primary)
                        .opacity(count == 0 ? 0.45 : 1)
                    }
                    .buttonStyle(.plain)
                    // 개수를 붙이면 접근성 라벨이 "서울, 12"가 되어 이름으로 못 찾는다 →
                    // 식별자는 이름 그대로 두고, 읽어 주는 문장에만 개수를 넣는다
                    .accessibilityIdentifier(title)
                    .accessibilityLabel(count.map { "\(title), \($0)개" } ?? title)
                    .accessibilityAddTraits(isOn ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 20)
        }
    }
}
