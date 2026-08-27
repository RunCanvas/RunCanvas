import SwiftUI

extension View {
    /// 어느 입력칸이 포커스돼 있든 키보드를 내린다 (FocusState 없이 쓰는 공용 헬퍼)
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// 빈 곳 탭 → 키보드 닫힘. 버튼·텍스트필드 탭은 그대로 동작한다.
    func dismissKeyboardOnTap() -> some View {
        onTapGesture { hideKeyboard() }
    }
}
