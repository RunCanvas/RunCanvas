import SwiftUI
import SwiftData
import UIKit

/// 저장·공유 시트 — 편집 화면 위에 올라온다 (예전 4/4 단계였던 CanvasExportView 대체)
struct CanvasExportSheet: View {
    let background: CanvasBackground
    let run: Run
    let stickers: [CanvasSticker]
    /// 사진 앱이든 앱 내부든 한 번이라도 저장하면 알린다 (편집 화면이 나갈 때 안 물어보도록)
    let onSaved: () -> Void
    /// 앱에 저장까지 끝나면 편집 화면도 닫는다
    let onSavedToApp: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var renderedImage: UIImage?
    @State private var renderFailed = false
    @State private var showsShareSheet = false
    /// 공유용 PNG 임시 파일 — UIImage 를 그대로 넘기면 투명 배경을 잃는다
    @State private var shareURL: URL?
    @State private var showsOverwriteConfirmation = false
    @State private var message: ExportMessage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                preview

                if background.isTransparent {
                    Text("체크무늬는 미리보기용이며 저장되지 않아요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    PrimaryButton(title: "사진 앱에 저장", systemImage: "square.and.arrow.down") {
                        Task { await saveToPhotos() }
                    }
                    .disabled(renderedImage == nil)

                    HStack(spacing: 10) {
                        SecondaryButton(title: "공유", systemImage: "square.and.arrow.up") {
                            // 공유도 내보내기다 — didSave 를 안 세우면 편집기를 닫을 때
                            // 이미 내보낸 사용자에게 "꾸미던 내용을 버릴까요?"가 뜬다
                            onSaved()
                            if let renderedImage {
                                shareURL = try? CanvasExporter.pngFileForSharing(renderedImage, runID: run.id)
                            }
                            showsShareSheet = true
                        }
                        SecondaryButton(title: "앱에 저장", systemImage: "tray.and.arrow.down") {
                            // 같은 기록을 다시 꾸미면 이전 이미지를 덮어쓰므로 먼저 알린다
                            if run.decoratedImageFilename == nil { saveToApp() } else { showsOverwriteConfirmation = true }
                        }
                    }
                    .disabled(renderedImage == nil)
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 20)
            .navigationTitle("저장")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .task { render() }
        .sheet(isPresented: $showsShareSheet) {
            // PNG 파일 URL로 넘긴다 — UIImage 를 그대로 주면 투명 배경이 사라진다(CanvasExporter 주석 참고).
            // 파일을 못 만들면 이미지로라도 공유한다(투명도는 잃지만 공유 자체는 되게).
            if let shareURL { ShareSheet(items: [shareURL]) }
            else if let renderedImage { ShareSheet(items: [renderedImage]) }
        }
        .confirmationDialog("이미 저장한 런꾸가 있어요", isPresented: $showsOverwriteConfirmation, titleVisibility: .visible) {
            Button("덮어쓰기") { saveToApp() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 기록에 저장된 런꾸 이미지를 새 이미지로 바꿔요.")
        }
        .alert(
            message?.isSuccess == true ? "저장 완료" : "저장할 수 없어요",
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } }),
            presenting: message
        ) { message in
            if message.opensSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("설정 열기", destination: url)
            }
            Button("확인") {
                if message.finishesFlow { dismiss(); onSavedToApp() }
            }
        } message: { message in
            Text(message.text)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let renderedImage {
            Image(uiImage: renderedImage)
                .resizable()
                .scaledToFit()
                .background {
                    if background.isTransparent { TransparencyGrid() }
                }
                .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
                .padding(.horizontal, 20)
        } else if renderFailed {
            VStack(spacing: 12) {
                Text("이미지를 만들지 못했어요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("다시 시도") { render() }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView("이미지 만드는 중…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @MainActor
    private func render() {
        renderFailed = false
        renderedImage = CanvasExporter.render(background: background, run: run, stickers: stickers)
        renderFailed = renderedImage == nil   // nil을 안 보면 스피너가 영원히 돈다
    }

    @MainActor
    private func saveToPhotos() async {
        guard let renderedImage else { return }
        do {
            try await CanvasExporter.savePNGToPhotos(renderedImage)
            onSaved()
            message = ExportMessage(text: "사진 앱에 PNG로 저장했어요.", isSuccess: true)
        } catch {
            let opensSettings: Bool
            if let exportError = error as? CanvasExporter.ExportError, case .notAuthorized = exportError {
                opensSettings = true
            } else {
                opensSettings = false
            }
            message = ExportMessage(
                text: error.localizedDescription,
                isSuccess: false,
                opensSettings: opensSettings
            )
        }
    }

    private func saveToApp() {
        guard let renderedImage else { return }
        // 실패 시 되돌릴 이전 값 — 안 되돌리면 파일은 안 썼는데 모델은 새 파일을 가리키거나,
        // 반대로 방금 쓴 파일이 즉시 고아가 된다 (삭제 경로는 이미 같은 방식으로 복구한다)
        let previous = run.decoratedImageFilename
        do {
            run.decoratedImageFilename = try CanvasStorage.save(image: renderedImage, runID: run.id, preservesTransparency: background.isTransparent)
            try context.save()
            onSaved()
            message = ExportMessage(text: "이 러닝의 상세 화면에 저장했어요.", isSuccess: true, finishesFlow: true)
        } catch {
            run.decoratedImageFilename = previous
            message = ExportMessage(text: "런꾸를 저장하지 못했어요. 저장 공간을 확인한 뒤 다시 시도해 주세요.", isSuccess: false)
        }
    }
}

private struct ExportMessage {
    let text: String
    let isSuccess: Bool
    var opensSettings = false
    var finishesFlow = false
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
