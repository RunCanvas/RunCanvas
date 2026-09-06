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

    /// 골격이 서로 다른 세 가지 — 산세리프 / 세리프 / 라운드.
    /// 같은 시스템 폰트의 무게만 바꾸면 셋이 구분되지 않아서, design과 weight를 함께 달리한다.
    enum FontStyle: String, CaseIterable, Identifiable {
        case modern = "모던"
        case serif = "세리프"
        case round = "라운드"

        var id: String { rawValue }

        var design: Font.Design {
            switch self {
            case .modern: .default
            case .serif: .serif
            case .round: .rounded
            }
        }

        var weight: Font.Weight {
            switch self {
            case .modern: .black
            case .serif: .semibold
            case .round: .heavy
            }
        }

        /// 숫자를 크게 쓰는 스티커(거리 등)에서 글자 사이를 조인다
        var tracking: CGFloat {
            switch self {
            case .modern: -1
            case .serif: 0
            case .round: -0.5
            }
        }

        /// 인스펙터에서 "Aa"를 실제 글꼴로 보여줄 때 쓴다
        var sampleFont: Font { .system(size: 19, weight: weight, design: design) }
    }

    let id: UUID
    var kind: Kind
    /// 캔버스 크기에 독립적인 0...1 정규화 좌표.
    var position: CGPoint
    var scale: CGFloat
    /// 스티커 기울기 (핀치와 함께 두 손가락으로 돌린다)
    var rotation: Angle
    var opacity: Double
    var fontStyle: FontStyle
    var color: Color

    init(
        id: UUID = UUID(),
        kind: Kind,
        position: CGPoint = CGPoint(x: 0.5, y: 0.5),
        scale: CGFloat = 1,
        rotation: Angle = .zero,
        opacity: Double = 1,
        fontStyle: FontStyle = .modern,
        color: Color = .white
    ) {
        self.id = id
        self.kind = kind
        self.position = position
        self.scale = scale
        self.rotation = rotation
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
