import SwiftUI

/// 트레이닝 프로그램 목록 — 앱에 담긴 프로그램과 내가 만든 프로그램.
struct TrainingProgramListView: View {
    @Environment(AuthService.self) private var auth
    @State private var custom: [TrainingProgram] = []
    @State private var showsEditor = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                section("짜여 있는 프로그램", programs: TrainingProgram.builtIn)

                HStack {
                    Text("내가 만든 프로그램").font(.headline)
                    Spacer()
                    Button("새로 만들기") { showsEditor = true }
                        .frame(minHeight: 44).contentShape(Rectangle())
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.top, 14)

                if custom.isEmpty {
                    Text("직접 만든 프로그램이 여기 쌓입니다. 걷기·달리기 구간을 원하는 대로 짜 보세요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    ForEach(custom) { program in
                        card(program)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
        .navigationTitle("트레이닝")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsEditor, onDismiss: reload) {
            ProgramEditorView(program: nil, ownerID: auth.userID)
        }
        .onAppear(perform: reload)
    }

    private func section(_ title: String, programs: [TrainingProgram]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            ForEach(programs) { card($0) }
        }
    }

    private func card(_ program: TrainingProgram) -> some View {
        NavigationLink {
            TrainingProgramDetailView(program: program, ownerID: auth.userID)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(program.name).font(.headline)
                    Spacer()
                    Text("\(TrainingStore.completedCount(in: program, ownerID: auth.userID))/\(program.sessions.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(program.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(value: Double(TrainingStore.completedCount(in: program, ownerID: auth.userID)),
                             total: Double(max(1, program.sessions.count)))
                    .tint(.primary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func reload() {
        custom = TrainingStore.customPrograms(ownerID: auth.userID)
    }
}
