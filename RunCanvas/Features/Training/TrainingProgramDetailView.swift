import SwiftUI

/// 프로그램 하나 — 세션 목록에서 오늘 할 것을 골라 시작한다.
struct TrainingProgramDetailView: View {
    let program: TrainingProgram
    let ownerID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var completed: Set<UUID> = []
    @State private var showsEditor = false
    @State private var showsDeleteConfirm = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(program.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(program.sessions) { session in
                    NavigationLink {
                        TrainingRunView(program: program, session: session, ownerID: ownerID)
                    } label: {
                        row(session)
                    }
                    .buttonStyle(.plain)
                }

                if !program.isBuiltIn {
                    HStack(spacing: 16) {
                        Button("편집") { showsEditor = true }
                        Button("삭제", role: .destructive) { showsDeleteConfirm = true }
                    }
                    .font(.subheadline)
                    .padding(.top, 8)
                }
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { completed = TrainingStore.completedSessionIDs(ownerID: ownerID) }
        .sheet(isPresented: $showsEditor) {
            ProgramEditorView(program: program, ownerID: ownerID)
        }
        .confirmationDialog("이 프로그램을 삭제할까요?", isPresented: $showsDeleteConfirm, titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                TrainingStore.delete(program, ownerID: ownerID)
                dismiss()
            }
            Button("취소", role: .cancel) {}
        }
    }

    private func row(_ session: TrainingSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: completed.contains(session.id) ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(completed.contains(session.id) ? Color.primary : Color.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title).font(.subheadline.weight(.semibold))
                Text("\(session.totalSeconds / 60)분 · 달리기 \(session.runningSeconds / 60)분 · 구간 \(session.steps.count)개")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
