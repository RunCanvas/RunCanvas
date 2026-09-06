import XCTest
import SwiftUI
import UIKit
@testable import RunCanvas

final class CanvasThemeTests: XCTestCase {

    // MARK: - hex 왕복

    func testHexRoundTrip() {
        for preset in CanvasTheme.presets {
            let color = CanvasTheme.color(hex: preset.hex)
            XCTAssertNotNil(color, preset.name)
            XCTAssertEqual(CanvasTheme.hex(color!), preset.hex, preset.name)
        }
    }

    /// ColorPicker 가 sRGB 밖(P3)의 색을 줘도 6자리를 유지해야 다시 읽을 수 있다
    func testHexClampsOutOfRangeColor() {
        let wide = Color(.displayP3, red: 1, green: 0, blue: 0)
        XCTAssertEqual(CanvasTheme.hex(wide).count, 6)
        XCTAssertNotNil(CanvasTheme.color(hex: CanvasTheme.hex(wide)))
    }

    func testInvalidHexIsRejected() {
        XCTAssertNil(CanvasTheme.color(hex: ""))
        XCTAssertNil(CanvasTheme.color(hex: "FFF"))
        XCTAssertNil(CanvasTheme.color(hex: "GGGGGG"))
        XCTAssertNil(CanvasTheme.color(hex: "#FFFFFF"))
    }

    // MARK: - 색 결정 규칙

    /// 빈 값("배경에 맞춤")은 예전 동작 그대로 배경 대비색을 쓴다
    func testAutoFollowsBackground() {
        XCTAssertEqual(CanvasTheme.resolvedColor(hex: "", background: .preset(.midnight)), .white)
        XCTAssertEqual(CanvasTheme.resolvedColor(hex: "", background: .preset(.paper)), .black)
        XCTAssertEqual(CanvasTheme.resolvedColor(hex: "", background: .photo(UIImage())), .white)
    }

    /// 페이퍼(밝은 배경) 위의 흰 글씨는 안 보이므로 검정으로 물러난다
    func testWhiteOnPaperFallsBackToBlack() {
        XCTAssertEqual(CanvasTheme.resolvedColor(hex: "FFFFFF", background: .preset(.paper)), .black)
    }

    /// 반대로 어두운 배경 위의 검정도 물러난다 (사진 배경 포함 — 사진은 어두운 쪽으로 본다)
    func testBlackOnDarkBackgroundFallsBackToWhite() {
        XCTAssertEqual(CanvasTheme.resolvedColor(hex: "000000", background: .preset(.midnight)), .white)
        XCTAssertEqual(CanvasTheme.resolvedColor(hex: "000000", background: .photo(UIImage())), .white)
    }

    /// 대비가 충분하면 고른 색을 그대로 쓴다
    func testReadableColorIsKept() {
        let resolved = CanvasTheme.resolvedColor(hex: "F5C417", background: .preset(.midnight))
        XCTAssertEqual(CanvasTheme.hex(resolved), "F5C417")
    }

    /// 어떤 프리셋 색을 골라도, 어떤 배경에서도 최소 대비는 지켜진다 (폴백이 항상 통해야 한다)
    func testEveryPresetStaysReadableOnEveryBackground() {
        for preset in CanvasTheme.presets {
            for canvasPreset in CanvasPreset.allCases {
                let background = CanvasBackground.preset(canvasPreset)
                let resolved = CanvasTheme.resolvedColor(hex: preset.hex, background: background)
                let gap = abs(CanvasTheme.luminance(resolved) - CanvasTheme.luminance(of: background))
                XCTAssertGreaterThanOrEqual(
                    gap, CanvasTheme.contrastThreshold,
                    "\(preset.name) / \(canvasPreset.title)"
                )
            }
        }
    }
}
