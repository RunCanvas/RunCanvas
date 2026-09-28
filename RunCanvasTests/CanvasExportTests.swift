import XCTest
import UIKit
@testable import RunCanvas

final class CanvasExportTests: XCTestCase {
    private func sampleRun() -> Run {
        Run(ownerID: UUID(), startedAt: Date(), endedAt: Date(), distanceMeters: 1000, movingSeconds: 360, calories: 60)
    }

    private func alpha(_ image: UIImage, x: Int = 0, y: Int = 0) throws -> UInt8 {
        let cg = try XCTUnwrap(image.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: -x, y: -y, width: cg.width, height: cg.height))
        return pixel[3]
    }

    @MainActor
    func testTransparentExportPreservesStickersAndClearCornersAfterPNGEncoding() throws {
        let image = try XCTUnwrap(CanvasExporter.quickCard(for: sampleRun()))
        let decoded = try XCTUnwrap(UIImage(data: XCTUnwrap(image.pngData())))
        XCTAssertEqual(decoded.size, CanvasExporter.size)
        XCTAssertEqual(try alpha(decoded), 0)
        // Default card contains visible content: inspect alpha over the full bitmap.
        let cg = try XCTUnwrap(decoded.cgImage)
        var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: cg.width, height: cg.height,
            bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 })
    }

    @MainActor
    func testDefaultBackgroundRemainsOpaque() throws {
        let image = try XCTUnwrap(CanvasExporter.quickCard(for: sampleRun(), background: .preset(.midnight)))
        XCTAssertEqual(try alpha(image), 255)
    }

    @MainActor
    func testEachCanvasFormatRendersAtItsExportSize() throws {
        let run = sampleRun()
        let stickers = CanvasStudioView.defaultStickers(for: run, color: .white)

        for format in [CanvasFormat.story, .portrait, .square] {
            let image = try XCTUnwrap(CanvasExporter.render(
                background: .transparent,
                run: run,
                stickers: stickers,
                format: format
            ))
            XCTAssertEqual(image.size, format.outputSize(for: .transparent))
        }
    }

    func testOriginalFormatUsesBackgroundPhotoRatio() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 900)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 1600, height: 900)))
        }
        let background = CanvasBackground.photo(image)

        XCTAssertEqual(CanvasFormat.original.aspectRatio(for: background), 16.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(CanvasFormat.original.outputSize(for: background), CGSize(width: 1920, height: 1080))
    }

    @MainActor
    func testLocalPNGStorageKeepsTransparency() throws {
        let id = UUID()
        let image = try XCTUnwrap(CanvasExporter.quickCard(for: sampleRun()))
        let filename = try CanvasStorage.save(image: image, runID: id, preservesTransparency: true)
        defer { CanvasStorage.delete(filename: filename) }
        XCTAssertTrue(filename.hasSuffix(".png"))
        let loaded = try XCTUnwrap(CanvasStorage.image(filename: filename))
        XCTAssertEqual(try alpha(loaded), 0)
    }
}
