import SwiftUI
import SwiftData

/// 런꾸 탭 — 앱의 밝은 톤 그대로. 저장해 둔 런꾸를 모아 보고, 편집기는 여기서 **전체 화면으로 덮어** 연다.
/// (인스타처럼: 목록은 앱 톤, 편집기는 별도 전체 화면 surface)
struct CanvasHomeView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        NavigationStack {
            CanvasGallery(ownerID: auth.userID)
                .navigationTitle("런꾸")
        }
    }
}

private struct CanvasGallery: View {
    @Query private var runs: [Run]
    @State private var thumbnails: [UUID: UIImage] = [:]
    @State private var editingRun: Run?
    @State private var isCreating = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    init(ownerID: UUID?) {
        let owner = ownerID ?? .noOwner
        _runs = Query(filter: #Predicate<Run> { $0.ownerID == owner }, sort: \Run.startedAt, order: .reverse)
    }

    /// 런꾸 이미지를 저장해 둔 기록만
    private var decorated: [Run] {
        runs.filter { $0.decoratedImageFilename != nil }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                PrimaryButton(title: "새로 꾸미기", systemImage: "wand.and.stars") {
                    isCreating = true
                }
                .disabled(runs.isEmpty)

                if runs.isEmpty {
                    hint("러닝을 한 번 기록하면 꾸밀 수 있어요.")
                } else if decorated.isEmpty {
                    hint("아직 저장한 런꾸가 없어요. 위에서 새로 꾸며 보세요.")
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(decorated) { run in
                            Button { editingRun = run } label: {
                                thumbnail(for: run)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(RunMath.formatKm(run.distanceMeters))킬로미터 런꾸, 다시 꾸미기")
                        }
                    }
                }
            }
            .padding(20)
        }
        .task(id: decorated.map(\.id)) { await loadThumbnails() }
        .fullScreenCover(isPresented: $isCreating) {
            CanvasStudioView()
        }
        .fullScreenCover(item: $editingRun) { run in
            CanvasStudioView(run: run)
        }
    }

    private func thumbnail(for run: Run) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let image = thumbnails[run.id] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.card
            }

            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)

            Text("\(RunMath.formatKm(run.distanceMeters)) km")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(10)
        }
        .aspectRatio(4 / 5, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 24)
    }

    /// 썸네일은 디스크에서 읽어 디코드하므로 메인 스레드 밖에서
    private func loadThumbnails() async {
        for run in decorated where thumbnails[run.id] == nil {
            let filename = run.decoratedImageFilename
            let image = await Task.detached(priority: .userInitiated) {
                CanvasStorage.image(filename: filename)
            }.value
            if let image { thumbnails[run.id] = image }
        }
    }
}

#Preview {
    CanvasHomeView()
        .environment(AuthService())
        .modelContainer(for: Run.self, inMemory: true)
}
