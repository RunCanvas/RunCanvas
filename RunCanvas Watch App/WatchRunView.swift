import SwiftUI

struct WatchRunView: View {
    @StateObject private var workout = WatchWorkoutManager()
    @State private var showsEndConfirm = false
    @State private var didPhoneRecord = false

    var body: some View {
        ZStack {
            WatchPalette.background.ignoresSafeArea()

            switch workout.state {
            case .idle:
                readyView
            case .running, .paused:
                activeRunView
            case .finished:
                finishedView
            }
        }
        .onChange(of: workout.isPhoneRecording) { _, recording in
            // 종료 시점엔 스냅샷이 이미 끊겨 있으므로, 러닝 중에 한 번이라도 받아 갔는지를 기억해 둔다.
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
        .confirmationDialog("러닝을 종료할까요?", isPresented: $showsEndConfirm, titleVisibility: .visible) {
            Button("종료", role: .destructive) {
                Task { await workout.end() }
            }
        }
    }

    // MARK: - 대기

    private var readyView: some View {
        VStack(spacing: 10) {
            Text("RUN CANVAS")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.8)
                .foregroundStyle(WatchPalette.lime)

            ZStack {
                Circle()
                    .fill(WatchPalette.surface)
                    .frame(width: 64, height: 64)
                Image(systemName: "figure.run")
                    .font(.system(size: 31, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("달릴 준비됐나요?")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

            Button {
                Task { await workout.start() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill")
                    Text(workout.isStarting ? "준비 중" : "러닝 시작")
                }
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(WatchPalette.lime, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(workout.isStarting)

            connectionLabel
        }
        .padding(.horizontal, 8)
    }

    // MARK: - 러닝 중

    /// 첫 페이지는 수치, 둘째 페이지는 조작에 집중한다.
    /// 40mm Series 5에서도 숫자를 크게 유지하면서 오탭을 줄이기 위한 구조다.
    private var activeRunView: some View {
        TabView {
            metricsPage
            controlsPage
        }
        .tabViewStyle(.verticalPage)
    }

    private var metricsPage: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Circle()
                    .fill(workout.state == .paused ? WatchPalette.orange : WatchPalette.lime)
                    .frame(width: 6, height: 6)
                Text(workout.state == .paused ? "PAUSED" : "RUNNING")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.72))
                Spacer(minLength: 2)
                connectionIcon
            }

            VStack(alignment: .leading, spacing: -4) {
                Text("DISTANCE")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(WatchPalette.lime)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.2f", workout.displayedDistanceMeters / 1_000))
                        .font(.system(size: 43, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("KM")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                }
            }

            Capsule()
                .fill(WatchPalette.lime)
                .frame(height: 2)

            HStack(spacing: 5) {
                statCard(title: "TIME", value: formatDuration(workout.displayedElapsedSeconds), accent: .white)
                statCard(title: "PACE", value: formatPace(workout.displayedPaceSecondsPerKm), accent: WatchPalette.lime)
                statCard(title: "BPM", value: workout.heartRate.map { "\(Int($0))" } ?? "--", accent: WatchPalette.coral)
            }

            HStack(spacing: 3) {
                Spacer()
                Image(systemName: "chevron.down")
                Text("컨트롤")
                Spacer()
            }
            .font(.system(size: 8, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 7)
    }

    private var controlsPage: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(workout.state == .paused ? "일시정지됨" : "러닝 중")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                Text(formatDuration(workout.displayedElapsedSeconds))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .monospacedDigit()
            }

            HStack(spacing: 14) {
                if workout.state == .paused {
                    roundControlButton(systemImage: "play.fill", title: "계속", tint: WatchPalette.lime) {
                        workout.resume()
                    }
                } else {
                    roundControlButton(systemImage: "pause.fill", title: "일시정지", tint: WatchPalette.orange) {
                        workout.pause()
                    }
                }

                roundControlButton(systemImage: "stop.fill", title: "종료", tint: WatchPalette.coral) {
                    showsEndConfirm = true
                }
            }

            Label("위로 넘겨 기록 보기", systemImage: "chevron.up")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 8)
    }

    // MARK: - 종료

    private var finishedView: some View {
        ScrollView {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(WatchPalette.lime.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(WatchPalette.lime)
                }

                Text("러닝 완료")
                    .font(.system(size: 18, weight: .black, design: .rounded))

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.2f", workout.displayedDistanceMeters / 1_000))
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .monospacedDigit()
                    Text("KM")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Text(finishedMessage)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.68))

                Button {
                    Task { await workout.start() }
                } label: {
                    Text("새 러닝")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(WatchPalette.lime, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(workout.isStarting)
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - 공통 UI

    private var finishedMessage: String {
        if !RunSavePolicy.shouldSave(distanceMeters: workout.displayedDistanceMeters) {
            return "50m 이하라 저장하지 않았어요"
        }
        return didPhoneRecord
            ? "iPhone에 저장됐어요"
            : "건강 앱에 저장됐어요\niPhone 앱을 열면 옮겨져요"
    }

    private var connectionLabel: some View {
        Label(
            workout.isPhoneReachable ? "iPhone 연결됨" : "Apple Watch로 기록",
            systemImage: workout.isPhoneReachable ? "iphone.radiowaves.left.and.right" : "applewatch"
        )
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.5))
    }

    private var connectionIcon: some View {
        Image(systemName: isPhoneKeepingRecord ? "iphone.radiowaves.left.and.right" : "applewatch")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(isPhoneKeepingRecord ? WatchPalette.lime : .white.opacity(0.48))
            .accessibilityLabel(isPhoneKeepingRecord ? "iPhone 동기화" : "Apple Watch 기록")
    }

    private func statCard(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(accent.opacity(0.72))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background(WatchPalette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func roundControlButton(
        systemImage: String,
        title: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(tint)
                        .frame(width: 58, height: 58)
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(.black)
                }
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .buttonStyle(.plain)
    }

    /// RunMath.formatDuration과 같은 규칙 — RunMath.swift가 워치 타깃에 없어 복사했다.
    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    private func formatPace(_ secondsPerKm: Double?) -> String {
        guard let secondsPerKm, secondsPerKm.isFinite else { return "--'--\"" }
        let rounded = max(0, Int(secondsPerKm.rounded()))
        return String(format: "%d'%02d\"", rounded / 60, rounded % 60)
    }

    /// 폰에 '닿는다'와 폰이 '기록한다'는 다르다. 시작 직후 20초까지는 동기화 판단을 미룬다.
    private var isPhoneKeepingRecord: Bool {
        guard workout.state == .running || workout.state == .paused,
              workout.displayedElapsedSeconds > 20 else { return workout.isPhoneReachable }
        return workout.isPhoneRecording
    }
}

private enum WatchPalette {
    static let background = Color.black
    static let surface = Color.white.opacity(0.09)
    static let lime = Color(red: 0.76, green: 1.0, blue: 0.12)
    static let orange = Color(red: 1.0, green: 0.66, blue: 0.12)
    static let coral = Color(red: 1.0, green: 0.30, blue: 0.27)
}

#Preview {
    WatchRunView()
}
