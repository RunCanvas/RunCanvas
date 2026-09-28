import CoreGraphics
import UIKit

/// 편집 화면과 저장 이미지가 함께 쓰는 캔버스 비율.
/// 좌표는 0...1 정규화라 비율을 바꿔도 스티커의 상대 위치는 유지된다.
enum CanvasFormat: String, CaseIterable, Identifiable {
    case story
    case portrait
    case square
    case original

    var id: String { rawValue }

    var title: String {
        switch self {
        case .story: "스토리"
        case .portrait: "피드 세로"
        case .square: "정사각형"
        case .original: "원본"
        }
    }

    var ratioLabel: String {
        switch self {
        case .story: "9:16"
        case .portrait: "4:5"
        case .square: "1:1"
        case .original: "사진 비율"
        }
    }

    var systemImage: String {
        switch self {
        case .story: "rectangle.portrait"
        case .portrait: "rectangle.portrait"
        case .square: "square"
        case .original: "photo"
        }
    }

    func aspectRatio(for background: CanvasBackground) -> CGFloat {
        switch self {
        case .story: return 9 / 16
        case .portrait: return 4 / 5
        case .square: return 1
        case .original:
            guard case .photo(let image) = background,
                  image.size.width > 0, image.size.height > 0 else { return 4 / 5 }
            return image.size.width / image.size.height
        }
    }

    /// SNS 업로드에 충분한 해상도를 유지하면서 지나치게 긴 원본 사진은 1920px 안에 맞춘다.
    func outputSize(for background: CanvasBackground) -> CGSize {
        switch self {
        case .story: return CGSize(width: 1080, height: 1920)
        case .portrait: return CGSize(width: 1080, height: 1350)
        case .square: return CGSize(width: 1080, height: 1080)
        case .original:
            let ratio = aspectRatio(for: background)
            if ratio >= 1 {
                let width = min(1920, 1080 * ratio)
                return CGSize(width: width.rounded(), height: (width / ratio).rounded())
            } else {
                let height = min(1920, 1080 / ratio)
                return CGSize(width: (height * ratio).rounded(), height: height.rounded())
            }
        }
    }
}
