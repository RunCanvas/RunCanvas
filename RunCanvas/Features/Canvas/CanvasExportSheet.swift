import SwiftUI
import SwiftData
import UIKit

/// 저장·공유 시트 — 편집 화면 위에 올라온다 (예전 4/4 단계였던 CanvasExportView 대체)
struct CanvasExportSheet: View {
    let background: CanvasBackground
    let run: Run
    let stickers: [CanvasSticker]
    /// 앱에 저장까지 끝나면 편집 화면도 닫는다
    let onSavedToApp: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var renderedImage: UIImage?
    @State private var renderFailed = false
    @State private var showsShareSheet = false
    @State private var showsOverwriteConfirmation = false
    @State private var message: ExportMessage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                preview

                VStack(spacing: 10) {
                    PrimaryButton(title: "사진 앱에 저장", systemImage: "square.and.arrow.down") {
                        Task { await saveToPhotos() }
                    }
                    .disabled(renderedImage == nil)

                    HStack(spacing: 10) {
                        secondaryButton("공유", systemImage: "square.and.arrow.up") { showsShareSheet = true }
                        secondaryButton("앱에 저장", systemImage: "tray.and.arrow.down") {
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
            if let renderedImage { ShareSheet(items: [renderedImage]) }
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

    private func secondaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
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
            message = ExportMessage(text: "사진 앱에 PNG로 저장했어요.", isSuccess: true)
        } catch {
            message = ExportMessage(text: error.localizedDescription, isSuccess: false)
        }
    }

    private func saveToApp() {
        guard let renderedImage else { return }
        do {
            run.decoratedImageFilename = try CanvasStorage.save(image: renderedImage, runID: run.id)
            try context.save()
            message = ExportMessage(text: "이 러닝의 상세 화면에 저장했어요.", isSuccess: true, finishesFlow: true)
        } catch {
            message = ExportMessage(text: error.localizedDescription, isSuccess: false)
        }
    }
}

private struct ExportMessage {
    let text: String
    let isSuccess: Bool
    var finishesFlow = false
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
