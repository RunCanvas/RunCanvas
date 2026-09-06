import SwiftUI

/// 프로그램 만들기·고치기. 세션마다 구간(걷기·달리기·분)을 늘렸다 줄였다 한다.
/// 내장 프로그램을 열면 복제본을 고치는 것으로 시작한다 — 원본은 건드리지 않는다.
struct ProgramEditorView: View {
    let ownerID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: TrainingProgram

    init(program: TrainingProgram?, ownerID: UUID?) {
        self.ownerID = ownerID
        if let program {
            var copy = program
            if program.isBuiltIn {
                copy.id = UUID()
                copy.name = program.name + " (내 버전)"
                copy.isBuiltIn = false
                copy.sessions = program.sessions.map { session in
                    var s = session
                    s.id = UUID()
                    return s
                }
            }
            _draft = State(initialValue: copy)
        } else {
            _draft = State(initialValue: TrainingProgram(
                name: "",
                summary: "",
                sessions: [TrainingSession(title: "1일차", steps: [
                    TrainingStep(kind: .warmup, seconds: 300),
                    TrainingStep(kind: .run, seconds: 600),
                    TrainingStep(kind: .cooldown, seconds: 300)
                ])]
            ))
        }
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
            && draft.sessions.allSatisfy { !$0.steps.isEmpty }
    }

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
                    } header: {
                        Text("\(session.title) · \(session.totalSeconds / 60)분")
                    }
                    .listRowBackground(Color.card)
                }
                .onDelete { draft.sessions.remove(atOffsets: $0) }

                Section {
                    Button("세션 추가", systemImage: "plus.circle") {
                        draft.sessions.append(TrainingSession(
                            title: "\(draft.sessions.count + 1)일차",
                            steps: [TrainingStep(kind: .run, seconds: 600)]
                        ))
                    }
                    .font(.subheadline)
                }
                .listRowBackground(Color.card)
            }
            .listStyle(.insetGrouped)
            .appListTone()
            .navigationTitle(draft.name.isEmpty ? "새 프로그램" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        TrainingStore.save(draft, ownerID: ownerID)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func stepRow(_ step: Binding<TrainingStep>) -> some View {
        HStack {
            Picker("", selection: step.kind) {
                ForEach(TrainingStep.Kind.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            Spacer()
            // 30초 단위 — 초 단위로 고르게 하면 손가락만 아프고 훈련은 달라지지 않는다
            Stepper(value: step.seconds, in: 30...3_600, step: 30) {
                Text(step.wrappedValue.minutesText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .frame(maxWidth: 160)
        }
    }
}
