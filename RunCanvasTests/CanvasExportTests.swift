import XCTest
import UIKit
@testable import RunCanvas

final class CanvasExportTests: XCTestCase {
    private func run() -> Run {
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
        let image = try XCTUnwrap(CanvasExporter.quickCard(for: run()))
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
        let image = try XCTUnwrap(CanvasExporter.quickCard(for: run(), background: .preset(.midnight)))
        XCTAssertEqual(try alpha(image), 255)
    }

    @MainActor
    func testLocalPNGStorageKeepsTransparency() throws {
        let id = UUID()
        let image = try XCTUnwrap(CanvasExporter.quickCard(for: run()))
        let filename = try CanvasStorage.save(image: image, runID: id, preservesTransparency: true)
        defer { CanvasStorage.delete(filename: filename) }
        XCTAssertTrue(filename.hasSuffix(".png"))
        let loaded = try XCTUnwrap(CanvasStorage.image(filename: filename))
        XCTAssertEqual(try alpha(loaded), 0)
    }
}
