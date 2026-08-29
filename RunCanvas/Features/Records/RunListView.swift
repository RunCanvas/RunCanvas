import SwiftUI
import SwiftData

/// 전체 기록 목록 (날짜 역순) — 탭하면 상세, 왼쪽 스와이프로 삭제. 삭제해도 이미 딴 뱃지는 유지한다.
struct RunListView: View {
    @Environment(\.modelContext) private var context
    @Query private var runs: [Run]

    init(ownerID: UUID?) {
        let owner = ownerID ?? .noOwner
        _runs = Query(filter: #Predicate<Run> { $0.ownerID == owner }, sort: \Run.startedAt, order: .reverse)
    }

    var body: some View {
        List {
            ForEach(runs) { run in
                RunHistoryRow(run: run)
                    .background {
                        NavigationLink { RunDetailView(run: run) } label: { EmptyView() }
                            .opacity(0)   // List가 붙이는 꺾쇠 숨김 (행에 이미 있음)
                    }
                    .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
            }
            .onDelete { offsets in
                let deleted = offsets.map { runs[$0] }
                let ids = deleted.map(\.id)
                deleted.compactMap(\.decoratedImageFilename).forEach(CanvasStorage.delete)   // 꾸민 이미지도 같이
                deleted.forEach(context.delete)
                try? context.save()
                // 서버에서도 지운다 — 안 지우면 다음 동기화가 그대로 되살린다
                Task { await SyncService.deleteRemote(runIDs: ids) }
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
    }
}

#Preview {
    NavigationStack { RunListView(ownerID: nil) }
        .modelContainer(for: Run.self, inMemory: true)
}
