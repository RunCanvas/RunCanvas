import SwiftUI
import UIKit

/// 런꾸 기록 색상 테마 — 설정에서 기본 색을 미리 정해 두면 새로 꾸밀 때 그 색으로 시작한다.
/// 저장은 `@AppStorage(CanvasTheme.storageKey)` 에 6자리 hex 문자열 하나.
/// 빈 문자열은 "배경에 맞춤"(지금까지의 동작)이라서, 기본값이 그대로 예전 동작이 된다.
enum CanvasTheme {
    static let storageKey = "canvasStickerColorHex"

    struct Preset: Identifiable {
        let name: String
        let hex: String
        var id: String { hex }
    }

    /// 편집기 팔레트(`Studio.swatches`)에서 뽑은 색 — 설정과 편집기의 색 어휘를 같게 둔다
    static let presets: [Preset] = [
        Preset(name: "화이트", hex: "FFFFFF"),
        Preset(name: "블랙", hex: "000000"),
        Preset(name: "옐로", hex: "F5C417"),
        Preset(name: "코랄", hex: "F0525A"),
        Preset(name: "민트", hex: "33BAC7"),
        Preset(name: "라벤더", hex: "D4A8E8")
    ]

    /// 배경과 밝기 차가 이보다 작으면 글씨가 배경에 묻힌다고 본다
    static let contrastThreshold = 0.25

    // MARK: - 색 결정 규칙 (순수 함수)

    /// 저장된 테마 색을 실제 스티커 색으로 바꾼다.
    /// "배경에 맞춤"(빈 값)이거나 배경과 밝기가 비슷해 안 보일 색이면 배경 대비색(흰/검정)으로 물러난다.
    /// — 페이퍼 배경 위의 흰 글씨처럼, 사용자가 모르고 고른 조합이 그대로 저장되는 걸 막는다.
    static func resolvedColor(hex: String, background: CanvasBackground) -> Color {
        guard let color = color(hex: hex) else { return background.foregroundColor }
        let gap = abs(luminance(color) - luminance(of: background))
        return gap < contrastThreshold ? background.foregroundColor : color
    }

    /// 배경 밝기 — 프리셋은 그러데이션 두 색의 평균, 사진은 알 수 없어 어두운 쪽으로 본다
    /// (사진 위에는 지금도 흰 글씨를 기본으로 쓴다)
    static func luminance(of background: CanvasBackground) -> Double {
        switch background {
        case .preset(let preset):
            preset.colors.map { luminance($0) }.reduce(0, +) / Double(preset.colors.count)
        case .photo:
            0
        }
    }

    /// 사람 눈 기준 밝기 근사. 감마 보정을 뺀 가중 평균이라 WCAG 대비비는 아니지만,
    /// "이 색이 이 배경에 묻히나"를 가르는 데는 충분하다.
    static func luminance(_ color: Color) -> Double {
        let (r, g, b) = components(color)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    // MARK: - hex 변환 (AppStorage 는 문자열만 담는다)

    static func color(hex: String) -> Color? {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// `ColorPicker` 는 sRGB 밖(P3)의 색도 주므로 0...1 로 자른다.
    /// 안 자르면 "100" 같은 세 자리가 섞여 7자리가 되고, 그러면 다시 못 읽는다.
    static func hex(_ color: Color) -> String {
        let (r, g, b) = components(color)
        return String(format: "%02X%02X%02X", channel(r), channel(g), channel(b))
    }

    private static func channel(_ value: Double) -> Int {
        Int((min(max(value, 0), 1) * 255).rounded())
    }

    private static func components(_ color: Color) -> (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }
}
