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
    /// 삭제 확인 중인 기록. nil 이면 대화상자를 닫는다
    @State private var runToDelete: Run?
    @State private var deleteError: String?
    @Environment(\.modelContext) private var context

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private let ownerID: UUID?

    init(ownerID: UUID?) {
        self.ownerID = ownerID
        let owner = ownerID ?? .noOwner
        _runs = Query(filter: #Predicate<Run> { $0.ownerID == owner }, sort: \Run.startedAt, order: .reverse)
    }

    /// 런꾸 이미지를 저장해 둔 기록만
    private var decorated: [Run] {
        runs.filter { $0.decoratedImageFilename != nil }
    }

    // 한 덩어리로 두면 타입 체커가 시간 안에 못 푼다 → 화면·격자·시트를 나눠 둔다
    var body: some View {
        gallery
            .task(id: decorated.map(\.id)) { await loadThumbnails() }
            .fullScreenCover(isPresented: $isCreating, onDismiss: reloadThumbnails) {
                CanvasStudioView()
            }
            .fullScreenCover(item: $editingRun, onDismiss: reloadThumbnails) { run in
                CanvasStudioView(run: run)
            }
            .confirmationDialog(
                "런꾸를 삭제할까요?",
                isPresented: isShowingDeleteConfirmation,
                titleVisibility: .visible,
                presenting: runToDelete
            ) { run in
                Button("런꾸 삭제", role: .destructive) { deleteDecoration(for: run) }
                Button("취소", role: .cancel) {}
            } message: { _ in
                Text("러닝 기록은 남고 저장한 이미지만 삭제돼요.")
            }
            .alert("삭제할 수 없어요", isPresented: isShowingDeleteError) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
    }

    private var gallery: some View {
        ScrollView {
            VStack(spacing: 24) {
                PrimaryButton(title: "새로 꾸미기", systemImage: "wand.and.stars") {
                    isCreating = true
                }
                .disabled(runs.isEmpty)

                NavigationLink {
                    RecapView(ownerID: ownerID)
                } label: {
                    SecondaryButtonLabel(title: "이달의 러닝 정산", systemImage: "calendar")
                }
                .buttonStyle(.plain)

                if runs.isEmpty {
                    hint("러닝을 한 번 기록하면 꾸밀 수 있어요.")
                } else if decorated.isEmpty {
                    hint("아직 저장한 런꾸가 없어요. 위에서 새로 꾸며 보세요.")
                } else {
                    grid
                }
            }
            .padding(20)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(decorated) { run in
                Button { editingRun = run } label: {
                    thumbnail(for: run)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("런꾸 삭제", systemImage: "trash", role: .destructive) {
                        runToDelete = run
                    }
                }
                .accessibilityAction(named: "런꾸 삭제") { runToDelete = run }
                .accessibilityLabel("\(RunMath.formatKm(run.distanceMeters))킬로미터 런꾸, 다시 꾸미기")
            }
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

    private var isShowingDeleteConfirmation: Binding<Bool> {
        Binding(
            get: { runToDelete != nil },
            set: { if !$0 { runToDelete = nil } }
        )
    }

    private var isShowingDeleteError: Binding<Bool> {
        Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )
    }

    private func reloadThumbnails() {
        // 같은 파일명으로 덮어써도 새 이미지를 읽도록 편집기가 닫힐 때 메모리 캐시를 비운다.
        thumbnails.removeAll()
        Task { await loadThumbnails() }
    }

    private func deleteDecoration(for run: Run) {
        guard let filename = run.decoratedImageFilename else { return }
        run.decoratedImageFilename = nil
        do {
            // 파일부터 지우면 SwiftData 저장 실패 때 기록이 사라진 파일을 계속 가리키게 된다.
            try context.save()
            CanvasStorage.delete(filename: filename)
            thumbnails[run.id] = nil
        } catch {
            run.decoratedImageFilename = filename
            deleteError = "저장한 런꾸를 삭제하지 못했어요. 다시 시도해 주세요."
        }
    }

    /// 그리드에 필요한 크기로 백그라운드에서 디코드해 원본 이미지가 메모리에 쌓이지 않게 한다.
    private func loadThumbnails() async {
        for run in decorated where thumbnails[run.id] == nil {
            let filename = run.decoratedImageFilename
            let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let image = CanvasStorage.image(filename: filename) else { return nil }
                return await image.byPreparingThumbnail(ofSize: CGSize(width: 540, height: 675))
            }.value
            guard !Task.isCancelled, run.decoratedImageFilename == filename else { continue }
            if let image { thumbnails[run.id] = image }
        }
    }
}

#Preview {
    CanvasHomeView()
        .environment(AuthService())
        .modelContainer(for: Run.self, inMemory: true)
}
