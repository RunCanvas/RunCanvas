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
                    Text("건강 앱에 저장됐어요")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Label(
                        workout.isPhoneReachable ? "iPhone 동기화" : "Watch 단독 기록",
                        systemImage: workout.isPhoneReachable ? "iphone.radiowaves.left.and.right" : "applewatch"
                    )
                    .font(.caption2)
                    .foregroundStyle(workout.isPhoneReachable ? .green : .secondary)
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
