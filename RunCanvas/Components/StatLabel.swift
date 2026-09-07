import SwiftUI

/// 작은 제목 + 값 (러닝 중·결과·상세 화면 공용)
struct StatLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}
