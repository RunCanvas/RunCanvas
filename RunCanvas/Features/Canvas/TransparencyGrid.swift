import SwiftUI

/// 화면에서만 투명 영역을 표시한다. 내보내는 StickerCanvas에는 넣지 않는다.
struct TransparencyGrid: View {
    var body: some View {
        Canvas { context, size in
            let side: CGFloat = 16
            for row in 0..<Int(ceil(size.height / side)) {
                for column in 0..<Int(ceil(size.width / side)) {
                    let rect = CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side)
                    context.fill(Path(rect), with: .color((row + column).isMultiple(of: 2)
                        ? Color(white: 0.55) : Color(white: 0.7)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
