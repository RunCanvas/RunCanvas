import SwiftUI

/// 프로그램 하나 — 오늘 할 세션을 맨 위에서 바로 시작하고, 나머지는 주차별로 접어 본다.
struct TrainingProgramDetailView: View {
    let program: TrainingProgram
    let ownerID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var completed: Set<UUID> = []
    @State private var showsEditor = false
    @State private var showsDeleteConfirm = false

    /// 아직 안 한 첫 세션 — 런데이처럼 "오늘 할 것"을 찾아 헤매지 않게 맨 위에 올린다
    private var nextSession: TrainingSession? {
        program.sessions.first { !completed.contains($0.id) }
    }

    private var doneCount: Int { program.sessions.count { completed.contains($0.id) } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                summaryCard

                if let nextSession {
                    resumeCard(nextSession)
                }

                ForEach(groups) { group in
                    Section {
                        ForEach(group.sessions) { session in
                            NavigationLink {
                                TrainingRunView(program: program, session: session, ownerID: ownerID)
                            } label: {
                                row(session)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        if groups.count > 1 {
                            HStack {
                                Text(group.id).font(.headline)
                                Spacer()
                                Text("\(group.sessions.count { completed.contains($0.id) })/\(group.sessions.count)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 6)
                            .background(Color(.systemBackground))
                        }
                    }
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

    // MARK: 조각

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(program.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(value: Double(doneCount), total: Double(max(1, program.sessions.count)))
                .tint(.primary)
            Text("\(doneCount)/\(program.sessions.count) 세션 완료")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func resumeCard(_ session: TrainingSession) -> some View {
        NavigationLink {
            TrainingRunView(program: program, session: session, ownerID: ownerID)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 38))
                VStack(alignment: .leading, spacing: 3) {
                    Text(doneCount == 0 ? "여기서 시작" : "이어서 하기")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(session.title).font(.headline)
                    Text("\(session.totalSeconds / 60)분 · 달리기 \(session.runningSeconds / 60)분")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
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

    // MARK: 주차 묶기

    private struct SessionGroup: Identifiable {
        let id: String
        let sessions: [TrainingSession]
    }

    /// "3주차 2일" → "3주차" 로 묶는다. 24세션을 한 줄로 늘어놓으면 어디까지 했는지 알 수 없다.
    private var groups: [SessionGroup] {
        var order: [String] = []
        var buckets: [String: [TrainingSession]] = [:]
        for session in program.sessions {
            let key = session.title.split(separator: " ").first.map(String.init) ?? session.title
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(session)
        }
        return order.map { SessionGroup(id: $0, sessions: buckets[$0] ?? []) }
    }
}
