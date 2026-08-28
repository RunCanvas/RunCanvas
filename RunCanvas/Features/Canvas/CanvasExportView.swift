import SwiftUI
import SwiftData
import Photos
import UIKit

struct CanvasExportView: View {
    let background: CanvasBackground
    let run: Run
    let stickers: [CanvasSticker]
    let onBack: () -> Void
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @State private var renderedImage: UIImage?
    @State private var showsShareSheet = false
    @State private var showsExitConfirmation = false
    @State private var message: ExportMessage?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let renderedImage {
                    Image(uiImage: renderedImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
                } else {
                    ProgressView("이미지 만드는 중…")
                        .frame(maxWidth: .infinity)
                        .frame(height: 360)
                }

                VStack(spacing: 10) {
                    PrimaryButton(title: "사진 앱에 저장", systemImage: "square.and.arrow.down") {
                        Task { await saveToPhotos() }
                    }
                    .disabled(renderedImage == nil)

                    Button {
                        showsShareSheet = true
                    } label: {
                        Label("공유", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.card)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(renderedImage == nil)

                    Button("앱에 저장") { saveToApp() }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .buttonStyle(.plain)
                        .disabled(renderedImage == nil)

                    Button { onBack() } label: {
                        Label("다시 수정", systemImage: "pencil")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.card)
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        showsExitConfirmation = true
                    } label: {
                        Label("저장하지 않고 꾸미기 종료", systemImage: "xmark.circle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundStyle(.red)
                            .background(Color.red.opacity(0.06))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.red.opacity(0.55), lineWidth: 1)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .padding(.bottom, 72)
        }
        .navigationTitle("런꾸 4/4")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { onBack() } label: { Label("이전", systemImage: "chevron.left") }
            }
        }
        .task { render() }
        .sheet(isPresented: $showsShareSheet) {
            if let renderedImage { ShareSheet(items: [renderedImage]) }
        }
        .confirmationDialog(
            "꾸미기를 종료할까요?",
            isPresented: $showsExitConfirmation,
            titleVisibility: .visible
        ) {
            Button("저장하지 않고 종료", role: .destructive) { onDone() }
            Button("계속 꾸미기", role: .cancel) {}
        } message: {
            Text("사진 앱이나 앱 내부에 저장하지 않은 내용은 남지 않아요.")
        }
        .alert(item: $message) { message in
            Alert(
                title: Text(message.isSuccess ? "저장 완료" : "저장할 수 없어요"),
                message: Text(message.text),
                dismissButton: .default(Text("확인"), action: message.finishesFlow ? onDone : {})
            )
        }
    }

    @MainActor
    private func render() {
        let content = StickerCanvas(
            background: background,
            run: run,
            stickers: .constant(stickers),
            selectedStickerID: .constant(nil),
            isEditing: false
        )
        .frame(width: 1080, height: 1350)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderedImage = renderer.uiImage
    }

    private func saveToPhotos() async {
        guard let renderedImage else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            message = ExportMessage(text: "설정에서 사진 추가 권한을 허용해주세요.", isSuccess: false)
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: renderedImage)
            }
            message = ExportMessage(text: "사진 앱에 고해상도 이미지로 저장했어요.", isSuccess: true)
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

private struct ExportMessage: Identifiable {
    let id = UUID()
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

