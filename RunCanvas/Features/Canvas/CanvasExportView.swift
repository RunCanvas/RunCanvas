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
    @State private var renderFailed = false
    @State private var showsShareSheet = false
    @State private var showsExitConfirmation = false
    @State private var showsOverwriteConfirmation = false
    @State private var message: ExportMessage?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let renderedImage {
                    // 저장되는 이미지가 직각이라 미리보기도 라운드를 주지 않는다
                    Image(uiImage: renderedImage)
                        .resizable()
                        .scaledToFit()
                        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
                } else if renderFailed {
                    VStack(spacing: 12) {
                        Text("이미지를 만들지 못했어요.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("다시 시도") { render() }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
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

                    // 같은 기록을 다시 꾸미면 이전 이미지를 덮어쓰므로 먼저 알린다
                    Button("앱에 저장") {
                        if run.decoratedImageFilename == nil {
                            saveToApp()
                        } else {
                            showsOverwriteConfirmation = true
                        }
                    }
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

                    // 아무것도 지우지 않고 플로우만 끝내는 버튼이라 위험해 보이지 않게 앱 톤으로
                    Button {
                        showsExitConfirmation = true
                    } label: {
                        Label("저장 안 하고 나가기", systemImage: "xmark.circle")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.card)
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
            Button("나가기") { onDone() }
            Button("계속 꾸미기", role: .cancel) {}
        } message: {
            Text("사진 앱이나 앱 내부에 저장하지 않은 내용은 남지 않아요.")
        }
        .confirmationDialog(
            "이미 저장한 런꾸가 있어요",
            isPresented: $showsOverwriteConfirmation,
            titleVisibility: .visible
        ) {
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
            Button("확인") { if message.finishesFlow { onDone() } }
        } message: { message in
            Text(message.text)
        }
    }

    @MainActor
    private func render() {
        renderFailed = false
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
        renderFailed = renderedImage == nil   // nil을 안 보면 스피너가 영원히 돈다
    }

    /// 권한 요청 뒤 백그라운드로 넘어가면 @State(message)를 메인 밖에서 건드리게 된다
    @MainActor
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

