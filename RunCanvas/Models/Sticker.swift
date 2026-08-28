import Foundation
import CoreGraphics
import SwiftUI

struct CanvasSticker: Identifiable {
    enum Kind {
        case distance
        case time
        case pace
        case date
        case calories
        case heartRate
        case route
        case badge(Badge)
        case text(String)
    }

    enum FontStyle: String, CaseIterable, Identifiable {
        case bold = "볼드"
        case rounded = "라운드"
        case mono = "모노"

        var id: String { rawValue }
    }

    let id: UUID
    var kind: Kind
    /// 캔버스 크기에 독립적인 0...1 정규화 좌표.
    var position: CGPoint
    var scale: CGFloat
    var opacity: Double
    var fontStyle: FontStyle
    var color: Color

    init(
        id: UUID = UUID(),
        kind: Kind,
        position: CGPoint = CGPoint(x: 0.5, y: 0.5),
        scale: CGFloat = 1,
        opacity: Double = 1,
        fontStyle: FontStyle = .bold,
        color: Color = .white
    ) {
        self.id = id
        self.kind = kind
        self.position = position
        self.scale = scale
        self.opacity = opacity
        self.fontStyle = fontStyle
        self.color = color
    }
}
