import Foundation
import UIKit

enum CanvasStorage {
    enum StorageError: LocalizedError {
        case jpegEncodingFailed

        var errorDescription: String? { "꾸민 이미지를 JPEG로 만들지 못했어요." }
    }

    static func save(image: UIImage, runID: UUID, fileManager: FileManager = .default) throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw StorageError.jpegEncodingFailed
        }
        let directory = try canvasDirectory(fileManager: fileManager)
        let filename = "\(runID.uuidString.lowercased()).jpg"
        try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
        return "canvas/\(filename)"
    }

    static func image(filename: String?, fileManager: FileManager = .default) -> UIImage? {
        guard let filename,
              let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return UIImage(contentsOfFile: documents.appendingPathComponent(filename).path)
    }

    /// 기록·계정을 지울 때 남는 파일 정리 (이미 없으면 조용히 무시)
    static func delete(filename: String) {
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? fileManager.removeItem(at: documents.appendingPathComponent(filename))
    }

    private static func canvasDirectory(fileManager: FileManager) throws -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("canvas", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
