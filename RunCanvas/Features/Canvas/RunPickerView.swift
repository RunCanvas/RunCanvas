import SwiftUI
import SwiftData

struct RunPickerView: View {
    let ownerID: UUID?
    let onSelect: (Run) -> Void

    var body: some View {
        CanvasRunList(ownerID: ownerID, onSelect: onSelect)
            .navigationTitle("런꾸 2/4")
            .navigationBarTitleDisplayMode(.inline)
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
