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

// MARK: - 레벨 컬러 = 앱 악센트 (NRC 팔레트)

extension Level.Tier {
    var color: Color {
        switch self {
        case .yellow: Color(red: 0.96, green: 0.77, blue: 0.09)
        case .orange: Color(red: 0.95, green: 0.42, blue: 0.11)
        case .green: Color(red: 0.18, green: 0.72, blue: 0.30)
        case .blue: Color(red: 0.12, green: 0.44, blue: 0.91)
        case .purple: Color(red: 0.48, green: 0.24, blue: 0.91)
        case .black: Color(red: 0.07, green: 0.07, blue: 0.07)
        case .volt: Color(red: 0.81, green: 1.0, blue: 0.0)
        }
    }

    /// 배경색 위 글자색
    var foreground: Color {
        switch self {
        case .yellow, .volt: .black
        default: .white
        }
    }

    /// 버튼·틴트용. 블랙 레벨은 다크 모드에서 검정 위 검정이 되므로 흑백(primary)으로
    var accent: Color { self == .black ? .primary : color }
    var onAccent: Color { self == .black ? Color(.systemBackground) : foreground }
}

/// 현재 계정의 레벨 — RootTabView가 넣어 주고, 버튼·진행바·차트가 악센트로 쓴다. 로그인 전(nil)은 흑백.
private struct LevelTierKey: EnvironmentKey {
    static let defaultValue: Level.Tier? = nil
}

extension EnvironmentValues {
    var levelTier: Level.Tier? {
        get { self[LevelTierKey.self] }
        set { self[LevelTierKey.self] = newValue }
    }
}
