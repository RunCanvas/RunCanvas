import SwiftUI
import SwiftData

/// 전체 기록 목록 (날짜 역순) — 탭하면 상세, 왼쪽 스와이프로 삭제. 삭제해도 이미 딴 뱃지는 유지한다.
struct RunListView: View {
    @Environment(\.modelContext) private var context
    @Query private var runs: [Run]
    private let ownerID: UUID
    @State private var pendingDeletion: [Run] = []
    @State private var deletionError: String?
    @State private var selectedRun: Run?

    init(ownerID: UUID?) {
        let owner = ownerID ?? .noOwner
        self.ownerID = owner
        _runs = Query(filter: #Predicate<Run> { $0.ownerID == owner }, sort: \Run.startedAt, order: .reverse)
    }

    var body: some View {
        List {
            ForEach(runs) { run in
                Button { selectedRun = run } label: {
                    RunHistoryRow(run: run)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("run-history-\(run.id.uuidString)")
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                    // 왜: .onDelete가 그리는 버튼은 앱에 ko 로컬라이즈가 없어 한국어 기기에서도 "Delete"로 뜬다.
                    // 직접 그려야 한국어로 보이고, 인덱스 대신 run을 그대로 넘겨 목록이 바뀌어도 안전하다.
                    .swipeActions(edge: .trailing) {
                        Button("삭제", role: .destructive) { pendingDeletion = [run] }
                    }
            }
        }
        .listStyle(.plain)
        .overlay {
            if runs.isEmpty {
                ContentUnavailableView("기록이 없어요", systemImage: "figure.run")
            }
        }
        .navigationTitle("전체 기록")
        .navigationBarTitleDisplayMode(.inline)
        // 숨긴 빈 링크 대신 실제 선택이 있을 때만 상세 화면을 만든다.
        .navigationDestination(item: $selectedRun) { run in
            RunDetailView(run: run)
        }
        .confirmationDialog("이 기록을 삭제할까요?", isPresented: Binding(
            get: { !pendingDeletion.isEmpty },
            set: { if !$0 { pendingDeletion = [] } }
        ), titleVisibility: .visible) {
            Button("삭제", role: .destructive) { deletePendingRuns() }
            Button("취소", role: .cancel) { pendingDeletion = [] }
        } message: {
            Text("기록과 저장한 런꾸 이미지가 함께 삭제돼요.")
        }
        .alert("기록을 삭제하지 못했어요", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(deletionError ?? "잠시 후 다시 시도해 주세요.")
        }
    }

    private func deletePendingRuns() {
        let deleted = pendingDeletion
        pendingDeletion = []
        let ids = deleted.map(\.id)
        let images = deleted.compactMap(\.decoratedImageFilename)
        deleted.forEach(context.delete)
        do {
            // 왜: 로컬 저장이 실패했는데 서버부터 지우면 다음 동기화에서 로컬 기록을 다시 올리거나
            // 서버 사본만 사라진다. 로컬 커밋 뒤에 파일·서버를 정리한다.
            try context.save()
            images.forEach(CanvasStorage.delete)
            Task { await SyncService.deleteRemote(runIDs: ids, ownerID: ownerID) }
        } catch {
            context.rollback()
            deletionError = (error as? LocalizedError)?.errorDescription ?? "기록을 지우지 못했어요. 잠시 후 다시 시도해 주세요."
        }
    }
}

#Preview {
    NavigationStack { RunListView(ownerID: nil) }
        .modelContainer(for: Run.self, inMemory: true)
}
