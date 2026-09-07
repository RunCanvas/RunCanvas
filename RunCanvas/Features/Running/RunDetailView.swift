import SwiftUI

/// 기록 상세: 지도 경로 + 수치. 홈·기록 목록에서 push, 결과 화면에서도 재사용.
struct RunDetailView: View {
    let run: Run

    /// 닉네임은 서버 프로필의 로컬 캐시 — 코스에 "누가 올렸는지"로 같이 올린다
    @AppStorage("userNickname") private var nickname = ""

    /// body에서 바로 디코드하면 화면이 다시 그려질 때마다 1080×1350 JPEG를 메인 스레드에서 푼다
    @State private var decoratedImage: UIImage?
    @State private var showsCourseRegister = false
    @State private var courseMessage: String?
    @State private var isSavingCard = false
    @State private var saveMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                RouteMapView(route: run.route)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                if let decoratedImage {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("나의 런꾸")
                            .font(.headline)
                        Image(uiImage: decoratedImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
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

                // 한국어 전용 앱 — 기기 로케일이 영어면 "September 6, 2026 at 5:23 PM"으로 나오므로 ko_KR 고정
                Text(run.startedAt.formatted(Date.FormatStyle(date: .long, time: .shortened, locale: Locale(identifier: "ko_KR"))))
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
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(isSavingCard)
            }
            .padding(20)
        }
        .navigationTitle("러닝 상세")
        .toolbar {
            // 경로가 없는 기록(워치 인계 실패 등)은 코스로 만들 게 없다
            if run.route.count > 1 {
                Button("코스로 등록") { showsCourseRegister = true }
            }
        }
        .sheet(isPresented: $showsCourseRegister) {
            CourseRegisterView(run: run, nickname: nickname) { course in
                courseMessage = "‘\(course.name)’ 코스를 올렸어요. 기록 탭 → 더보기 → 러닝 코스에서 볼 수 있어요."
            }
        }
        .alert("코스로 등록했어요", isPresented: Binding(
            get: { courseMessage != nil },
            set: { if !$0 { courseMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(courseMessage ?? "")
        }
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
