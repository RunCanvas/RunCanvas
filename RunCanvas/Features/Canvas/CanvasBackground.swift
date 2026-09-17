import SwiftUI
import UIKit

enum CanvasPreset: Int, CaseIterable, Identifiable {
    case midnight
    case sunrise
    case forest
    case ocean
    case lavender
    case paper

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .midnight: "미드나잇"
        case .sunrise: "선라이즈"
        case .forest: "포레스트"
        case .ocean: "오션"
        case .lavender: "라벤더"
        case .paper: "페이퍼"
        }
    }

    var colors: [Color] {
        switch self {
        case .midnight: [Color(red: 0.04, green: 0.05, blue: 0.09), Color(red: 0.17, green: 0.20, blue: 0.31)]
        case .sunrise: [Color(red: 1.00, green: 0.73, blue: 0.42), Color(red: 0.94, green: 0.32, blue: 0.35)]
        case .forest: [Color(red: 0.08, green: 0.27, blue: 0.20), Color(red: 0.40, green: 0.66, blue: 0.35)]
        case .ocean: [Color(red: 0.08, green: 0.30, blue: 0.55), Color(red: 0.20, green: 0.73, blue: 0.78)]
        case .lavender: [Color(red: 0.35, green: 0.24, blue: 0.55), Color(red: 0.83, green: 0.66, blue: 0.91)]
        case .paper: [Color(red: 0.96, green: 0.94, blue: 0.88), Color(red: 0.82, green: 0.78, blue: 0.69)]
        }
    }

    var foregroundColor: Color { self == .paper ? .black : .white }
}

enum CanvasBackground {
    case transparent
    case preset(CanvasPreset)
    case photo(UIImage)

    var isTransparent: Bool {
        if case .transparent = self { return true }
        return false
    }

    var foregroundColor: Color {
        switch self {
        case .transparent: .white
        case .preset(let preset): preset.foregroundColor
        case .photo: .white
        }
    }
}

struct CanvasBackgroundView: View {
    let background: CanvasBackground

    var body: some View {
        switch background {
        case .transparent:
            Color.clear
        case .preset(let preset):
            LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        case .photo(let image):
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .overlay(Color.black.opacity(0.12))
        }
    }
}
