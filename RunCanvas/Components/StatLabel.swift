import SwiftUI

/// 작은 제목 + 값 (러닝 중·결과·상세 화면 공용)
struct StatLabel: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
        .frame(maxWidth: .infinity)
    }
}
