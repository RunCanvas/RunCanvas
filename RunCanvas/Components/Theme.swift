import SwiftUI

extension Color {
    /// 홈·기록 화면 카드 색 — 설정류 리스트 셀도 이걸 써서 탭마다 톤이 달라 보이지 않게
    static let card = Color.gray.opacity(0.08)
}

extension View {
    /// 인셋 그룹 `List`를 홈·기록과 같은 톤으로: 시스템 배경(흰/검정) + 회색 카드 셀.
    /// 사용: `List { Group { … }.listRowBackground(Color.card) }.listStyle(.insetGrouped).appListTone()`
    func appListTone() -> some View {
        scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
    }
}
