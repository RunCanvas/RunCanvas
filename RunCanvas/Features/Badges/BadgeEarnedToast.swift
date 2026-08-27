import SwiftUI

/// 러닝 종료 후 새로 딴 뱃지 알림. 화면 위에 카드가 내려왔다가 3초 뒤 사라진다.
/// 사용: `.badgeEarnedToast($newBadges)` — 배열이 비어 있지 않으면 표시, 사라지면 비운다.
struct BadgeEarnedToast: View {
    let badges: [Badge]

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.primary).frame(width: 48, height: 48)
                Image(systemName: badges.first?.symbolName ?? "medal.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(.systemBackground))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(badges.count == 1 ? "새 뱃지를 땄어요" : "새 뱃지 \(badges.count)개를 땄어요")
                    .font(.subheadline.weight(.semibold))
                Text(badges.map(\.title).joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }
}

extension View {
    func badgeEarnedToast(_ badges: Binding<[Badge]>) -> some View {
        overlay(alignment: .top) {
            if !badges.wrappedValue.isEmpty {
                BadgeEarnedToast(badges: badges.wrappedValue)
                    .transition(.move(edge: .top).combined(with: .opacity))
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
