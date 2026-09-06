import SwiftUI

/// 기록 상세: 지도 경로 + 수치. 홈·기록 목록에서 push, 결과 화면에서도 재사용.
struct RunDetailView: View {
    let run: Run

    /// body에서 바로 디코드하면 화면이 다시 그려질 때마다 1080×1350 JPEG를 메인 스레드에서 푼다
    @State private var decoratedImage: UIImage?
    @State private var isSavingCard = false
    @State private var saveMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                RouteMapView(route: run.route)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                if let decoratedImage {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("나의 런꾸")
                            .font(.headline)
                        Image(uiImage: decoratedImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }

                VStack(spacing: 8) {
                    Text(RunMath.formatKm(run.distanceMeters)).font(.system(size: 56, weight: .bold))
                    Text("km").foregroundStyle(.secondary)
                }

                HStack(spacing: 0) {
                    StatLabel(title: "시간", value: RunMath.formatDuration(run.movingSeconds))
                    StatLabel(title: "페이스", value: RunMath.formatPace(run.paceSecondsPerKm))
                    StatLabel(title: "칼로리", value: "\(Int(run.calories.rounded()))")
                    StatLabel(title: "평균 BPM", value: run.averageHeartRate.map { "\(Int($0))" } ?? "--")
                }

                Text(run.startedAt.formatted(date: .long, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                // 꾸미기를 거치지 않고 기본 배치 그대로 한 장
                Button {
                    Task { await saveCard() }
                } label: {
                    Label(isSavingCard ? "저장하는 중…" : "이미지로 저장", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isSavingCard)
            }
            .padding(24)
        }
        .navigationTitle("러닝 상세")
        .navigationBarTitleDisplayMode(.inline)
        .alert("이미지 저장", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(saveMessage ?? "")
        }
        .task(id: run.decoratedImageFilename) {
            let filename = run.decoratedImageFilename
            decoratedImage = await Task.detached(priority: .userInitiated) {
                CanvasStorage.image(filename: filename)
            }.value
        }
    }

    @MainActor
    private func saveCard() async {
        isSavingCard = true
        defer { isSavingCard = false }
        guard let card = CanvasExporter.quickCard(for: run) else {
            saveMessage = CanvasExporter.ExportError.renderFailed.localizedDescription
            return
        }
        do {
            try await CanvasExporter.savePNGToPhotos(card)
            saveMessage = "사진 앱에 PNG로 저장했어요."
        } catch {
            saveMessage = error.localizedDescription
        }
    }
}
