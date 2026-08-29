import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

struct BackgroundPickerView: View {
    let onSelect: (CanvasBackground) -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var isLoadingPhoto = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("배경을 골라주세요")
                        .font(.title2.bold())
                    Text("나중에 사진과 기록 스티커를 자유롭게 배치할 수 있어요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(CanvasPreset.allCases) { preset in
                        Button {
                            onSelect(.preset(preset))
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                Text(preset.title)
                                    .font(.headline)
                                    .foregroundStyle(preset.foregroundColor)
                                    .padding(14)
                            }
                            .aspectRatio(4 / 5, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 12) {
                    PhotosPicker(selection: $photoItem, matching: .images, preferredItemEncoding: .compatible) {
                        sourceButton(
                            title: isLoadingPhoto ? "불러오는 중…" : "사진 앨범",
                            systemImage: "photo.on.rectangle",
                            isLoading: isLoadingPhoto
                        )
                    }
                    .disabled(isLoadingPhoto)

                    Button { requestCamera() } label: {
                        sourceButton(title: "카메라", systemImage: "camera")
                    }
                    .disabled(isLoadingPhoto)
                }
            }
            .padding(20)
        }
        .navigationTitle("런꾸 1/4")
        .navigationBarTitleDisplayMode(.inline)
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
                        errorMessage = "사진을 불러오지 못했어요."
                        return
                    }
                    onSelect(.photo(await downsampled(image)))
                } catch {
                    errorMessage = "사진을 불러오지 못했어요. 다른 사진으로 시도해 주세요."
                }
            }
        }
        .sheet(isPresented: $showsCamera) {
            CameraPicker { image in
                showsCamera = false
                guard let image else { return }
                Task { onSelect(.photo(await downsampled(image))) }
            }
            .ignoresSafeArea()
        }
        .alert("배경을 선택할 수 없어요", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func sourceButton(title: String, systemImage: String, isLoading: Bool = false) -> some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// 카메라는 권한이 거부돼 있으면 검은 화면만 뜨므로 미리 확인한다
    private func requestCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "이 기기에서는 카메라를 사용할 수 없어요."
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
                    errorMessage = cameraDeniedMessage
                }
            }
        default:
            errorMessage = cameraDeniedMessage
        }
    }

    private var cameraDeniedMessage: String {
        "설정 앱에서 카메라 권한을 허용해주세요."
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
