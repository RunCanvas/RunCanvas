import SwiftUI

/// 러닝 종료 후 새로 딴 뱃지 알림. 화면 위에 카드가 내려왔다가 3초 뒤 사라진다.
/// 사용: `.badgeEarnedToast($newBadges)` — 배열이 비어 있지 않으면 표시, 사라지면 비운다.
struct BadgeEarnedToast: View {
    let badges: [Badge]
    /// 성공 햅틱을 카드가 실제로 뜨는 순간에 맞춘다 — 부르는 쪽이 배열을 언제 채우든 화면과 손 느낌이 어긋나지 않게
    @State private var didAppear = false

    var body: some View {
        HStack(spacing: 14) {
            // 한 번에 여러 개를 따는 경우(첫 러닝 5km 등)가 흔해서 겹쳐 보여준다
            HStack(spacing: -18) {
                ForEach(badges.prefix(3), id: \.self) { badge in
                    BadgeArt(badge: badge, isEarned: true, size: 48)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(badges.count == 1 ? "새 뱃지를 땄어요" : "새 뱃지 \(badges.count)개를 땄어요")
                    .font(.subheadline.weight(.semibold))
                Text(badges.map(\.title).joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .sensoryFeedback(.success, trigger: didAppear)
        .onAppear {
            didAppear = true
            AccessibilityNotification.Announcement(
                "새 뱃지 \(badges.count)개: \(badges.map(\.title).joined(separator: ", "))"
            ).post()
        }
    }
}

extension View {
    func badgeEarnedToast(_ badges: Binding<[Badge]>) -> some View {
        overlay(alignment: .top) {
            if !badges.wrappedValue.isEmpty {
                Button {
                    withAnimation { badges.wrappedValue = [] }
                } label: {
                    BadgeEarnedToast(badges: badges.wrappedValue)
                }
                .buttonStyle(.plain)
                .edgeTransition(.top)
                .accessibilityHint("두 번 탭하여 닫기")
                .task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { badges.wrappedValue = [] }
                }
            }
        }
        .animation(.spring(duration: 0.4), value: badges.wrappedValue.isEmpty)
    }
}

#Preview {
    Color.clear
        .badgeEarnedToast(.constant([.fiveK, .streak3]))
}
