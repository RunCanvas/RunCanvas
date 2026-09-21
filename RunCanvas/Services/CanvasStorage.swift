import Foundation
import UIKit

enum CanvasStorage {
    enum StorageError: LocalizedError {
        case jpegEncodingFailed
        case pngEncodingFailed

        var errorDescription: String? { "꾸민 이미지 파일을 만들지 못했어요." }
    }

    static func save(image: UIImage, runID: UUID, fileManager: FileManager = .default, preservesTransparency: Bool = false) throws -> String {
        guard let data = preservesTransparency ? image.pngData() : image.jpegData(compressionQuality: 0.92) else {
            throw preservesTransparency ? StorageError.pngEncodingFailed : StorageError.jpegEncodingFailed
        }
        let directory = try canvasDirectory(fileManager: fileManager)
        let stem = runID.uuidString.lowercased()
        let ext = preservesTransparency ? "png" : "jpg"
        // 배경 종류를 바꿔 다시 저장하면 확장자가 갈려 이전 파일이 아무도 안 가리키는 고아로 남는다.
        // (Run.decoratedImageFilename 은 새 값으로 덮이고, 삭제 경로들은 현재 값 하나만 지운다)
        for stale in ["png", "jpg"] where stale != ext {
            try? fileManager.removeItem(at: directory.appendingPathComponent("\(stem).\(stale)"))
        }
        let filename = "\(stem).\(ext)"
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
