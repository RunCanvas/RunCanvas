import SwiftUI

/// 값이 많은 필터용 알약. 누르면 메뉴가 열린다.
///
/// 지역은 17개라 칩으로 늘어놓으면 가로 스크롤이 화면을 두 번 넘게 지나간다 —
/// 고르는 데 스크롤이 필요한 순간 칩의 장점(한눈에 보이고 한 번에 눌린다)이 사라진다.
/// 고른 값은 알약에 그대로 보여서, 접어 두어도 지금 뭘로 걸러져 있는지 알 수 있다.
struct FilterMenuPill: View {
    /// 아무것도 안 고른 상태에서 보여줄 이름 ("지역")
    let title: String
    let options: [String]
    /// 전체를 뜻하는 값 — 이게 골라져 있으면 알약은 흐린 채로 `title` 을 보여준다
    let allOption: String
    var counts: [String: Int] = [:]
    @Binding var selection: String

    private var isNarrowed: Bool { selection != allOption }

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    if let count = counts[option] {
                        Text("\(option) (\(count))").tag(option)
                    } else {
                        Text(option).tag(option)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(isNarrowed ? selection : title)
                    .font(.subheadline.weight(.semibold))
                if let count = counts[selection], isNarrowed {
                    Text("\(count)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color(.systemBackground).opacity(0.7))
                }
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            // 왜: 알약은 32pt 높이라 손가락 기준(44pt)에 못 미친다 — 모양은 두고 히트 영역만 넓힌다
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .background(isNarrowed ? Color.primary : Color.card, in: Capsule())
            .foregroundStyle(isNarrowed ? Color(.systemBackground) : .primary)
            // 보이는 알약은 작게 유지하되 메뉴를 여는 터치 영역은 44pt를 보장한다.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(title)
        .accessibilityLabel("\(title), 현재 \(selection)")
    }
}
