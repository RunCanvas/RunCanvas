import SwiftUI
import Photos
import UIKit

/// 런꾸 이미지를 만들고 사진 앱에 넣는 곳 — 편집 화면과 "바로 저장"이 같은 코드를 쓴다.
enum CanvasExporter {
    /// 리캡 카드와 기존 바로 저장이 쓰는 호환 크기. 런꾸 편집기는 선택한 `CanvasFormat`을 사용한다.
    static let size = CGSize(width: 1080, height: 1350)

    enum ExportError: LocalizedError {
        case renderFailed
        case pngEncodingFailed
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .renderFailed: "이미지를 만들지 못했어요."
            case .pngEncodingFailed: "PNG로 바꾸지 못했어요."
            case .notAuthorized: "설정에서 사진 추가 권한을 허용해주세요."
            }
        }
    }

    @MainActor
    static func render(
        background: CanvasBackground,
        run: Run,
        stickers: [CanvasSticker],
        format: CanvasFormat = .portrait
    ) -> UIImage? {
        let outputSize = format.outputSize(for: background)
        let content = StickerCanvas(
            background: background,
            run: run,
            canvasAspectRatio: format.aspectRatio(for: background),
            stickers: .constant(stickers),
            selection: .constant([]),
            isEditing: false
        )
        .frame(width: outputSize.width, height: outputSize.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.isOpaque = false
        return renderer.uiImage
    }

    /// 사진 앱에 **PNG로** 넣는다. UIImage를 그대로 넘기면 시스템이 형식을 정하므로 데이터로 직접 넣는다.
    static func savePNGToPhotos(_ image: UIImage) async throws {
        guard let data = image.pngData() else { throw ExportError.pngEncodingFailed }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw ExportError.notAuthorized }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }

    /// 공유용 PNG 임시 파일. UIActivityViewController 에 UIImage 를 그대로 넘기면 받는 쪽이 형식을
    /// 정해(대개 JPEG 평탄화) "배경 없음"으로 꾸민 투명 영역이 검정·흰색으로 채워져 나간다.
    /// 미리보기에 "체크무늬는 저장되지 않아요"라고 적어 둔 것과 결과가 달라지므로 파일 URL로 넘긴다.
    static func pngFileForSharing(_ image: UIImage, runID: UUID) throws -> URL {
        guard let data = image.pngData() else { throw ExportError.pngEncodingFailed }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunCanvas-\(runID.uuidString.prefix(8)).png")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 편집을 거치지 않고 기본 배치 그대로 한 장 만든다 ("기록에서 바로 저장")
    @MainActor
    static func quickCard(for run: Run, background: CanvasBackground = .transparent) -> UIImage? {
        return render(
            background: background,
            run: run,
            stickers: CanvasStudioView.defaultStickers(for: run, color: background.foregroundColor)
        )
    }
}
