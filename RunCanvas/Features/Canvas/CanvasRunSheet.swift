import SwiftUI
import SwiftData

/// 꾸밀 기록 고르기 시트
struct CanvasRunSheet: View {
    let ownerID: UUID?
    let onSelect: (Run) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CanvasRunList(ownerID: ownerID) { run in
                onSelect(run)
                dismiss()
            }
            .navigationTitle("기록 고르기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CanvasRunList: View {
    @Query private var runs: [Run]
    let onSelect: (Run) -> Void

    init(ownerID: UUID?, onSelect: @escaping (Run) -> Void) {
        let owner = ownerID ?? .noOwner
        _runs = Query(filter: #Predicate<Run> { $0.ownerID == owner }, sort: \Run.startedAt, order: .reverse)
        self.onSelect = onSelect
    }

    var body: some View {
        Group {
            if runs.isEmpty {
                ContentUnavailableView(
                    "꾸밀 기록이 없어요",
                    systemImage: "figure.run",
                    description: Text("러닝을 한 번 기록한 뒤 다시 와주세요.")
                )
            } else {
                List(runs) { run in
                    Button { onSelect(run) } label: {
                        RunHistoryRow(run: run)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }
        }
    }
}
