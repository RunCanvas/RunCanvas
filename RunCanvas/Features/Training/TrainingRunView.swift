import SwiftUI
import SwiftData

/// 훈련 세션 실행 화면. 구간 타이머가 주인공이고, GPS 기록은 평소 러닝과 똑같이 남는다
/// (`RunCoordinator`를 그대로 쓴다 — 훈련이라고 따로 저장할 이유가 없다).
struct TrainingRunView: View {
    let program: TrainingProgram
    let session: TrainingSession
    let ownerID: UUID?

    @Environment(RunCoordinator.self) private var runs
    @Environment(\.dismiss) private var dismiss
    @State private var elapsed = 0
    @State private var lastAnnouncedStep = -1
    @State private var didFinish = false

    private var run: RunSession { runs.session }
    private var progress: TrainingEngine.Progress? { TrainingEngine.progress(elapsed: elapsed, in: session) }

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var runs = runs

        VStack(spacing: 0) {
            header

            Spacer()

            if let progress {
                VStack(spacing: 10) {
                    Text(progress.step.kind.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(RunMath.formatDuration(progress.remainingSeconds))
                        .font(.system(size: 72, weight: .bold))
                        .monospacedDigit()
                    if let next = progress.next {
                        Text("다음 · \(next.kind.title) \(next.minutesText)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("마지막 구간이에요").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 56))
                    Text("훈련 완료").font(.title2.weight(.bold))
                }
            }

            Spacer()

            VStack(spacing: 14) {
                ProgressView(value: progress?.fraction ?? 1).tint(.primary)
                HStack {
                    Label(RunMath.formatKm(run.distanceMeters) + " km", systemImage: "figure.run")
                    Spacer()
                    Text("전체 \(RunMath.formatDuration(elapsed)) / \(RunMath.formatDuration(session.totalSeconds))")
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            controls
                .padding(.horizontal, 24)
                .padding(.top, 24)

            Spacer().frame(height: 30)
        }
        .background(Color(.systemBackground))
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(run.state == .running || run.state == .paused)
        .onAppear { if run.state == .idle { runs.start() } }
        .onReceive(ticker) { _ in tick() }
        .fullScreenCover(item: $runs.finishedRun, onDismiss: { dismiss() }) { finished in
            RunResultView(run: finished)
        }
    }

    private var header: some View {
        HStack {
            Text(program.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            Spacer()
            Text("구간 \((progress?.index ?? session.steps.count - 1) + 1)/\(session.steps.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            if run.state == .paused {
                Button("재개") { runs.resume() }
                    .buttonStyle(.borderedProminent)
                    .tint(.primary)
                    .foregroundStyle(Color(.systemBackground))
            } else {
                Button("일시정지") { runs.pause() }
                    .buttonStyle(.bordered)
            }
            Button(didFinish ? "저장하고 나가기" : "훈련 끝내기") { finish() }
                .buttonStyle(.bordered)
                .tint(.red)
        }
        .font(.headline)
        .frame(maxWidth: .infinity)
    }

    /// 매초: 흐른 시간을 러닝 세션에서 가져오고(일시정지가 그대로 반영된다) 구간이 바뀌면 한 번 알린다
    private func tick() {
        guard run.state == .running else { return }
        elapsed = run.elapsedSeconds
        guard let progress else {
            if !didFinish {
                didFinish = true
                run.announce(TrainingEngine.finishCue)
                TrainingStore.markCompleted(session, ownerID: ownerID)
            }
            return
        }
        if progress.index != lastAnnouncedStep {
            lastAnnouncedStep = progress.index
            run.announce(TrainingEngine.cue(for: progress))
        }
    }

    /// 중간에 끝내면 완료로 치지 않는다 — 완료 표시는 마지막 구간까지 간 tick 에서만 찍힌다
    private func finish() {
        _ = runs.finish(sendToWatch: true)
    }
}
