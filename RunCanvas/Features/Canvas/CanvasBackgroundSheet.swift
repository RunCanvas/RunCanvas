import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

/// 배경 고르기 시트 — 프리셋 / 앨범 / 카메라. 고르면 바로 닫힌다.
struct CanvasBackgroundSheet: View {
    let onSelect: (CanvasBackground) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var isLoadingPhoto = false
    @State private var errorMessage: BackgroundMessage?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 12) {
                        PhotosPicker(selection: $photoItem, matching: .images, preferredItemEncoding: .compatible) {
                            SecondaryButtonLabel(
                                title: isLoadingPhoto ? "불러오는 중…" : "사진 앨범",
                                systemImage: "photo.on.rectangle",
                                isLoading: isLoadingPhoto
                            )
                        }
                        .disabled(isLoadingPhoto)

                        SecondaryButton(title: "카메라", systemImage: "camera") { requestCamera() }
                        .disabled(isLoadingPhoto)
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        Button {
                            onSelect(.transparent)
                            dismiss()
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                TransparencyGrid()
                                Text("배경 없음")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .padding(14)
                                    .shadow(color: .black.opacity(0.7), radius: 3)
                            }
                            .aspectRatio(4 / 5, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)

                        ForEach(CanvasPreset.allCases) { preset in
                            Button {
                                onSelect(.preset(preset))
                                dismiss()
                            } label: {
                                ZStack(alignment: .bottomLeading) {
                                    LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                    Text(preset.title)
                                        .font(.headline)
                                        .foregroundStyle(preset.foregroundColor)
                                        .padding(14)
                                }
                                .aspectRatio(4 / 5, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .disabled(isLoadingPhoto)
                }
                .padding(20)
            }
            .navigationTitle("배경")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: photoItem) { _, item in
            guard let item, !isLoadingPhoto else { return }
            isLoadingPhoto = true
            Task {
                // 실패한 사진을 다시 고를 때도 onChange가 오도록 선택을 비운다
                defer { isLoadingPhoto = false; photoItem = nil }
                do {
                    // 시뮬레이터/일부 HEIC에서 loadTransferable이 영영 안 끝나는 경우가 있어 타임아웃을 건다
                    guard let data = try await withTimeoutValue(seconds: 20, { try await item.loadTransferable(type: Data.self) }),
                          let image = UIImage(data: data) else {
                        errorMessage = BackgroundMessage(text: "사진을 불러오지 못했어요.")
                        return
                    }
                    onSelect(.photo(await downsampled(image)))
                    dismiss()
                } catch {
                    errorMessage = BackgroundMessage(text: "사진을 불러오지 못했어요. 다른 사진으로 시도해 주세요.")
                }
            }
        }
        .sheet(isPresented: $showsCamera) {
            CameraPicker { image in
                showsCamera = false
                guard let image else { return }
                Task {
                    onSelect(.photo(await downsampled(image)))
                    dismiss()
                }
            }
            .ignoresSafeArea()
        }
        .alert("배경을 선택할 수 없어요", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        ), presenting: errorMessage) { message in
            if message.opensSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("설정 열기", destination: url)
            }
            Button("확인", role: .cancel) {}
        } message: {
            Text($0.text)
        }
    }

    /// 카메라는 권한이 거부돼 있으면 검은 화면만 뜨므로 미리 확인한다
    private func requestCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = BackgroundMessage(text: "이 기기에서는 카메라를 사용할 수 없어요.")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showsCamera = true
        case .notDetermined:
            Task {
                if await AVCaptureDevice.requestAccess(for: .video) {
                    showsCamera = true
                } else {
                    errorMessage = BackgroundMessage(
                        text: "설정 앱에서 카메라 권한을 허용해주세요.",
                        opensSettings: true
                    )
                }
            }
        default:
            errorMessage = BackgroundMessage(
                text: "설정 앱에서 카메라 권한을 허용해주세요.",
                opensSettings: true
            )
        }
    }

    /// 최종 산출물이 1080×1350이라 원본(수천만 화소)을 편집·렌더까지 들고 다닐 이유가 없다 — 긴 변 2160으로 줄인다
    private func downsampled(_ image: UIImage) async -> UIImage {
        let maxSide: CGFloat = 2160
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }
        let ratio = maxSide / longest
        let target = CGSize(
            width: (image.size.width * ratio).rounded(),
            height: (image.size.height * ratio).rounded()
        )
        return await image.byPreparingThumbnail(ofSize: target) ?? image
    }
}

private struct BackgroundMessage {
    let text: String
    var opensSettings = false
}

struct CameraPicker: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let completion: (UIImage?) -> Void

        init(completion: @escaping (UIImage?) -> Void) {
            self.completion = completion
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            completion(info[.originalImage] as? UIImage)
        }
    }
}
