import SwiftUI

/// 프로그램 만들기·고치기. 세션마다 구간(걷기·달리기·분)을 늘렸다 줄였다 한다.
/// 내장 프로그램을 열면 복제본을 고치는 것으로 시작한다 — 원본은 건드리지 않는다.
struct ProgramEditorView: View {
    let ownerID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: TrainingProgram
    @State private var pendingSessionDeletion: TrainingSession?
    @State private var showsDiscardConfirm = false
    private let original: TrainingProgram

    init(program: TrainingProgram?, ownerID: UUID?) {
        self.ownerID = ownerID
        let initialDraft: TrainingProgram
        if let program {
            var copy = program
            if program.isBuiltIn {
                copy.id = UUID()
                copy.name = program.name + " (내 버전)"
                copy.isBuiltIn = false
                copy.sessions = program.sessions.map { session in
                    var s = session
                    s.id = UUID()
                    s.steps = session.steps.map { step in
                        var copiedStep = step
                        copiedStep.id = UUID()
                        return copiedStep
                    }
                    return s
                }
            }
            initialDraft = copy
        } else {
            initialDraft = TrainingProgram(
                name: "",
                summary: "",
                sessions: [TrainingSession(title: "1일차", steps: [
                    TrainingStep(kind: .warmup, seconds: 300),
                    TrainingStep(kind: .run, seconds: 600),
                    TrainingStep(kind: .cooldown, seconds: 300)
                ])]
            )
        }
        original = initialDraft
        _draft = State(initialValue: initialDraft)
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.sessions.isEmpty
            && draft.sessions.allSatisfy { !$0.steps.isEmpty }
    }

    private var hasUnsavedChanges: Bool { draft != original }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("프로그램 이름", text: $draft.name)
                    TextField("한 줄 설명", text: $draft.summary, axis: .vertical)
                }
                .listRowBackground(Color.card)

                ForEach($draft.sessions) { $session in
                    Section {
                        TextField("세션 이름", text: $session.title)
                        ForEach($session.steps) { $step in
                            stepRow($step)
                        }
                        .onDelete { session.steps.remove(atOffsets: $0) }

                        Button("구간 추가", systemImage: "plus") {
                            session.steps.append(TrainingStep(kind: .run, seconds: 300))
                        }
                        .font(.subheadline)

                        Button("이 세션 삭제", role: .destructive) {
                            if session.steps.count >= 2 {
                                pendingSessionDeletion = session
                            } else {
                                deleteSession(id: session.id)
                            }
                        }
                    } header: {
                        Text("\(session.title) · \(session.totalSeconds / 60)분")
                    } footer: {
                        if session.steps.isEmpty {
                            Text("구간이 하나 이상 필요해요.")
                                .foregroundStyle(.red)
                        }
                    }
                    .listRowBackground(Color.card)
                }

                Section {
                    Button("세션 추가", systemImage: "plus.circle") {
                        draft.sessions.append(TrainingSession(
                            title: "\(draft.sessions.count + 1)일차",
                            steps: [TrainingStep(kind: .run, seconds: 600)]
                        ))
                    }
                    .font(.subheadline)
                } footer: {
                    if draft.sessions.isEmpty {
                        Text("세션이 하나 이상 필요해요.")
                            .foregroundStyle(.red)
                    }
                }
                .listRowBackground(Color.card)
            }
            .listStyle(.insetGrouped)
            .appListTone()
            .navigationTitle(draft.name.isEmpty ? "새 프로그램" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        if hasUnsavedChanges { showsDiscardConfirm = true }
                        else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        TrainingStore.save(draft, ownerID: ownerID)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .confirmationDialog(
                "이 세션을 삭제할까요?",
                isPresented: Binding(
                    get: { pendingSessionDeletion != nil },
                    set: { if !$0 { pendingSessionDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("세션 삭제", role: .destructive) {
                    if let id = pendingSessionDeletion?.id { deleteSession(id: id) }
                }
                Button("취소", role: .cancel) { pendingSessionDeletion = nil }
            } message: {
                Text("세션 안의 구간도 함께 삭제됩니다.")
            }
            .confirmationDialog("변경 내용을 버릴까요?", isPresented: $showsDiscardConfirm,
                                titleVisibility: .visible) {
                Button("변경 내용 버리기", role: .destructive) { dismiss() }
                Button("계속 편집", role: .cancel) {}
            }
        }
    }

    private func stepRow(_ step: Binding<TrainingStep>) -> some View {
        HStack {
            Picker("", selection: step.kind) {
                ForEach(TrainingStep.Kind.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .accessibilityLabel("구간 종류")
            Spacer()
            // 30초 단위 — 초 단위로 고르게 하면 손가락만 아프고 훈련은 달라지지 않는다
            Text(step.wrappedValue.minutesText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .layoutPriority(1)
            Stepper("구간 시간", value: step.seconds, in: 30...3_600, step: 30)
                .labelsHidden()
                .fixedSize()
        }
    }

    private func deleteSession(id: UUID) {
        draft.sessions.removeAll { $0.id == id }
        pendingSessionDeletion = nil
    }
}
