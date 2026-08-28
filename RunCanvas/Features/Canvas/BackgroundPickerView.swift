import SwiftUI
import PhotosUI
import UIKit

struct BackgroundPickerView: View {
    let onSelect: (CanvasBackground) -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var showsCamera = false
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
                        sourceButton(title: "사진 앨범", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            showsCamera = true
                        } else {
                            errorMessage = "이 기기에서는 카메라를 사용할 수 없어요."
                        }
                    } label: {
                        sourceButton(title: "카메라", systemImage: "camera")
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("런꾸 1/4")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    errorMessage = "사진을 불러오지 못했어요."
                    return
                }
                onSelect(.photo(image))
            }
        }
        .sheet(isPresented: $showsCamera) {
            CameraPicker { image in
                showsCamera = false
                if let image { onSelect(.photo(image)) }
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

    private func sourceButton(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
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
