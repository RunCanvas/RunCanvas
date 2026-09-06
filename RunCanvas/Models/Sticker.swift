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

        var design: Font.Design {
            switch self {
            case .bold: .default
            case .rounded: .rounded
            case .mono: .monospaced
            }
        }

        /// 인스펙터에서 "Aa"를 실제 글꼴로 보여줄 때 쓴다
        var sampleFont: Font { .system(size: 17, weight: .bold, design: design) }
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

extension CanvasSticker.Kind {
    /// 보이스오버가 읽어 줄 이름
    var accessibilityName: String {
        switch self {
        case .distance: "거리"
        case .time: "시간"
        case .pace: "페이스"
        case .date: "날짜"
        case .calories: "칼로리"
        case .heartRate: "심박수"
        case .route: "경로"
        case .badge(let badge): "\(badge.title) 뱃지"
        case .text(let text): text
        }
    }
}
