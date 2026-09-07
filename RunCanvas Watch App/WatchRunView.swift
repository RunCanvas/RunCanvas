import SwiftUI

struct WatchRunView: View {
    @StateObject private var workout = WatchWorkoutManager()
    @State private var showsEndConfirm = false

    var body: some View {
        ScrollView {
            // 왜: 앱 이름 제목을 빼야 40/41mm에서 일시정지·종료 버튼이 스크롤 없이 첫 화면에 들어온다
            VStack(spacing: 10) {
                // 왜: 종료 뒤 지표가 그대로 남아 있어 저장됐는지 알 수 없다 — 상태 라벨 자리를 빌려 알린다
                if workout.state == .finished {
                    // 왜: 예전엔 "건강 앱에 저장됐어요" 한 줄뿐이라, 사용자가 RunCanvas 에 남았는지를 알 수 없었다.
                    // 폰이 실시간으로 받아 갔으면 이미 앱에 있고, 아니면 앱을 열 때 건강 앱에서 가져온다.
                    Text(didPhoneRecord ? "iPhone에 저장됐어요" : "건강 앱에 저장됐어요\niPhone 앱을 열면 옮겨져요")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                } else {
                    Label(
                        isPhoneKeepingRecord ? "iPhone 동기화" : "건강 앱에만 저장",
                        systemImage: isPhoneKeepingRecord ? "iphone.radiowaves.left.and.right" : "applewatch"
                    )
                    .font(.caption2)
                    .foregroundStyle(isPhoneKeepingRecord ? .green : .secondary)
                }

                HStack(spacing: 12) {
                    metric(title: "BPM", value: workout.heartRate.map { "\(Int($0))" } ?? "--")
                    metric(title: "KM", value: String(format: "%.2f", workout.displayedDistanceMeters / 1_000))
                }

                Text(formatDuration(workout.displayedElapsedSeconds))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()

                controls
            }
            .padding(.horizontal, 4)
        }
        .onChange(of: workout.isPhoneRecording) { _, recording in
            // 종료 시점엔 스냅샷이 이미 끊겨 있으므로, 러닝 중에 한 번이라도 받아 갔는지를 기억해 둔다
            if recording { didPhoneRecord = true }
        }
        .onChange(of: workout.state) { _, state in
            if state == .running, workout.displayedElapsedSeconds < 3 { didPhoneRecord = false }
        }
        .alert("러닝을 처리할 수 없어요", isPresented: Binding(
            get: { workout.errorMessage != nil },
            set: { if !$0 { workout.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(workout.errorMessage ?? "")
        }
        // 왜: 종료는 되돌릴 수 없는데(HealthKit 마감 + 폰 저장) 일시정지 바로 옆이라 오탭이 잦다 — 한 번 더 묻는다
        .confirmationDialog("러닝을 종료할까요?", isPresented: $showsEndConfirm, titleVisibility: .visible) {
            Button("종료", role: .destructive) {
                Task { await workout.end() }
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch workout.state {
        case .idle, .finished:
            Button {
                Task { await workout.start() }
            } label: {
                Label("러닝 시작", systemImage: "figure.run")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(workout.isStarting)

        case .running:
            HStack {
                Button { workout.pause() } label: {
                    Image(systemName: "pause.fill")
                }
                .tint(.orange)

                endButton
            }
            .buttonStyle(.borderedProminent)

        case .paused:
            HStack {
                Button { workout.resume() } label: {
                    Image(systemName: "play.fill")
                }
                .tint(.green)

                endButton
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// 이번 러닝을 폰이 실제로 받아 갔는지. 종료 문구가 이걸로 갈린다.
    @State private var didPhoneRecord = false

    /// 왜: 폰에 '닿는다'와 폰이 '기록한다'는 다르다. 폰이 위치 권한 등으로 시작을 거절하면
    /// 닿아 있어도 스냅샷이 안 오는데, 그때 "iPhone 동기화"라고 쓰면 거짓말이 된다.
    /// 다만 시작 직후엔 명령이 큐로 가느라 폰 스냅샷이 아직 없으니 20초까지는 판단을 미룬다.
    private var isPhoneKeepingRecord: Bool {
        guard workout.state == .running || workout.state == .paused,
              workout.displayedElapsedSeconds > 20 else { return workout.isPhoneReachable }
        return workout.isPhoneRecording
    }

    private var endButton: some View {
        Button { showsEndConfirm = true } label: {
            Image(systemName: "stop.fill")
        }
        .tint(.red)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    /// RunMath.formatDuration과 같은 규칙 — RunMath.swift가 워치 타깃에 없어 복사했다.
    /// 왜: 1시간 넘는 러닝에서 "75:00"이 아니라 폰과 같은 "1:15:00"으로 보여야 한다
    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

#Preview {
    WatchRunView()
}
