import SwiftUI

struct WatchRunView: View {
    @StateObject private var workout = WatchWorkoutManager()

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("RunCanvas")
                    .font(.headline)

                Label(
                    workout.isPhoneReachable ? "iPhone 동기화" : "Watch 단독 기록",
                    systemImage: workout.isPhoneReachable ? "iphone.radiowaves.left.and.right" : "applewatch"
                )
                .font(.caption2)
                .foregroundStyle(workout.isPhoneReachable ? .green : .secondary)

                HStack(spacing: 12) {
                    metric(title: "BPM", value: workout.heartRate.map { "\(Int($0))" } ?? "--", color: .red)
                    metric(title: "KM", value: String(format: "%.2f", workout.displayedDistanceMeters / 1_000), color: .green)
                }

                Text(formatDuration(workout.displayedElapsedSeconds))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()

                controls
            }
            .padding(.horizontal, 4)
        }
        .alert("RunCanvas", isPresented: Binding(
            get: { workout.errorMessage != nil },
            set: { if !$0 { workout.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(workout.errorMessage ?? "")
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

        case .running:
            HStack {
                Button { workout.pause() } label: {
                    Image(systemName: "pause.fill")
                }
                .tint(.orange)

                Button {
                    Task { await workout.end() }
                } label: {
                    Image(systemName: "stop.fill")
                }
                .tint(.red)
            }
            .buttonStyle(.borderedProminent)

        case .paused:
            HStack {
                Button { workout.resume() } label: {
                    Image(systemName: "play.fill")
                }
                .tint(.green)

                Button {
                    Task { await workout.end() }
                } label: {
                    Image(systemName: "stop.fill")
                }
                .tint(.red)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func metric(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }

    private func formatDuration(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

#Preview {
    WatchRunView()
}
