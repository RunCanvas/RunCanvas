import SwiftUI

struct CanvasFlowView: View {
    private enum Step { case background, run, editor, export }

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .background
    @State private var background: CanvasBackground?
    @State private var selectedRun: Run?
    @State private var stickers: [CanvasSticker] = []
    private let skipsRunPicker: Bool

    init(run: Run? = nil) {
        _selectedRun = State(initialValue: run)
        skipsRunPicker = run != nil
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .background:
                    BackgroundPickerView { selected in
                        background = selected
                        step = selectedRun == nil ? .run : .editor
                    }
                case .run:
                    RunPickerView(ownerID: auth.userID) { run in
                        selectedRun = run
                        step = .editor
                    }
                case .editor:
                    if let background, let selectedRun {
                        StickerEditorView(
                            background: background,
                            run: selectedRun,
                            initialStickers: stickers,
                            onBack: { edited in
                                stickers = edited   // 이전으로 돌아가도 배치한 스티커를 잃지 않게
                                step = skipsRunPicker ? .background : .run
                            },
                            onExport: { edited in
                                stickers = edited
                                step = .export
                            }
                        )
                    } else {
                        stepFallback
                    }
                case .export:
                    if let background, let selectedRun {
                        CanvasExportView(
                            background: background,
                            run: selectedRun,
                            stickers: stickers,
                            onBack: { step = .editor },
                            onDone: { finishFlow() }
                        )
                    } else {
                        stepFallback
                    }
                }
            }
            .toolbar {
                if skipsRunPicker {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기") { dismiss() }
                    }
                }
            }
        }
    }

    /// 배경·기록이 어떤 이유로든 비면 툴바만 남은 빈 화면이 되므로 1단계로 돌려보낸다
    private var stepFallback: some View {
        Color.clear.onAppear { step = .background }
    }

    private func reset() {
        background = nil
        selectedRun = nil
        stickers = []
        step = .background
    }

    private func finishFlow() {
        if skipsRunPicker {
            dismiss()
        } else {
            reset()
        }
    }
}

#Preview {
    CanvasFlowView()
        .environment(AuthService())
        .modelContainer(for: Run.self, inMemory: true)
}
