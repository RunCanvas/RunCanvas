//
//  RunView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/24/26.
//

import SwiftUI
import SwiftData

/// 러닝 중 화면: 거리·시간·페이스·BPM, 시작/일시정지/재개, 종료 → 결과 화면
struct RunView: View {
    let startImmediately: Bool

    @Environment(AuthService.self) private var auth
    @EnvironmentObject private var watchConnectivity: WatchConnectivityService
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userWeight") private var userWeight: Double = 60
    @State private var session = RunSession(health: HealthService())
    @State private var finishedRun: Run?
    @State private var didRequestHealthAuthorization = false
    @State private var healthAuthorizationMessage: String?
    @State private var syncTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("러닝").font(.title2).bold()
                Spacer()
                Label(
                    watchConnectivity.isReachable ? "Watch 연결됨" : "iPhone 기록",
                    systemImage: watchConnectivity.isReachable ? "applewatch.radiowaves.left.and.right" : "iphone"
                )
                .font(.caption)
                .foregroundStyle(watchConnectivity.isReachable ? .green : .secondary)
            }
                .padding(.horizontal, 24).padding(.top, 20)

            Spacer()

            VStack(spacing: 8) {
                Text("거리").font(.subheadline).foregroundStyle(.secondary)
                Text(RunMath.formatKm(session.distanceMeters)).font(.system(size: 64, weight: .bold))
                Text("km").font(.title3).foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 0) {
                StatLabel(title: "시간", value: RunMath.formatDuration(session.elapsedSeconds))
                Divider().frame(height: 50)
                StatLabel(title: "페이스", value: RunMath.formatPace(RunMath.paceSecondsPerKm(distanceMeters: session.distanceMeters, seconds: session.elapsedSeconds)))
                Divider().frame(height: 50)
                StatLabel(title: "BPM", value: session.heartRate.map { "\(Int($0))" } ?? "--")
            }

            Spacer()

            PrimaryButton(
                title: session.state == .running ? "일시정지" : (session.state == .paused ? "재개" : "러닝 시작"),
                systemImage: session.state == .running ? "pause.fill" : "figure.run"
            ) {
                switch session.state {
                case .idle: startRun()
                case .running: pauseRun()
                case .paused: resumeRun()
                case .finished: break
                }
            }
            .padding(.horizontal, 24)

            if session.state == .running || session.state == .paused {
                Button("러닝 종료") { finish(sendToWatch: true) }
                    .font(.subheadline).foregroundStyle(.red).padding(.top, 16)
            }

            Spacer().frame(height: 30)
        }
        .navigationBarBackButtonHidden(session.state == .running || session.state == .paused)
        .task {
            guard !didRequestHealthAuthorization else { return }
            didRequestHealthAuthorization = true
            do {
                try await session.requestHealthAuthorization()
            } catch {
                healthAuthorizationMessage = error.localizedDescription
            }
            if startImmediately, session.state == .idle {
                startRun()
            }
        }
        .onAppear { configureWatchSync() }
        .onDisappear {
            syncTask?.cancel()
            syncTask = nil
            watchConnectivity.onCommand = nil
            watchConnectivity.onSnapshot = nil
        }
        .alert(
            "심박 기능을 사용할 수 없어요",
            isPresented: Binding(
                get: { healthAuthorizationMessage != nil },
                set: { if !$0 { healthAuthorizationMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(healthAuthorizationMessage ?? "러닝 기록은 계속 사용할 수 있어요.")
        }
        .fullScreenCover(item: $finishedRun, onDismiss: { dismiss() }) { run in
            RunResultView(run: run)
        }
    }

    private func startRun(sessionID: UUID = UUID(), sendToWatch: Bool = true) {
        let usesWatchWorkout = sendToWatch ? watchConnectivity.isReachable : true
        session.start(sessionID: sessionID, healthManagedExternally: usesWatchWorkout)

        guard sendToWatch, usesWatchWorkout else { return }
        watchConnectivity.sendCommand(.start, sessionID: sessionID) { succeeded in
            if !succeeded { session.takeOverHealthWorkout() }
        }
    }

    private func pauseRun(sendToWatch: Bool = true) {
        session.pause()
        if sendToWatch {
            watchConnectivity.sendCommand(.pause, sessionID: session.sessionID)
        }
    }

    private func resumeRun(sendToWatch: Bool = true) {
        session.resume()
        if sendToWatch {
            watchConnectivity.sendCommand(.resume, sessionID: session.sessionID)
        }
    }

    private func finish(sendToWatch: Bool) {
        guard let ownerID = auth.userID else { return }
        if sendToWatch {
            watchConnectivity.sendCommand(.end, sessionID: session.sessionID)
        }
        finishedRun = session.finish(ownerID: ownerID, weightKg: userWeight, context: context)
    }

    private func configureWatchSync() {
        watchConnectivity.onCommand = { action, remoteSessionID in
            switch action {
            case .start:
                guard session.state == .idle else { return }
                startRun(sessionID: remoteSessionID, sendToWatch: false)
            case .pause:
                guard remoteSessionID == session.sessionID else { return }
                pauseRun(sendToWatch: false)
            case .resume:
                guard remoteSessionID == session.sessionID else { return }
                resumeRun(sendToWatch: false)
            case .end:
                guard remoteSessionID == session.sessionID,
                      session.state == .running || session.state == .paused else { return }
                finish(sendToWatch: false)
            case .unavailable:
                guard remoteSessionID == session.sessionID else { return }
                session.takeOverHealthWorkout()
                healthAuthorizationMessage = "Apple Watch에서 운동을 시작하지 못해 iPhone 기록으로 전환했어요."
            }
        }

        watchConnectivity.onSnapshot = { snapshot in
            guard snapshot.sessionID == session.sessionID,
                  session.state == .running || session.state == .paused,
                  let heartRate = snapshot.heartRate else { return }
            if session.heartRate != heartRate {
                session.recordHeartRate(heartRate)
            }
        }

        syncTask?.cancel()
        syncTask = Task { @MainActor in
            while !Task.isCancelled {
                if watchConnectivity.isReachable,
                   session.state == .running || session.state == .paused {
                    watchConnectivity.sendSnapshot(
                        sessionID: session.sessionID,
                        state: session.state == .running ? "running" : "paused",
                        elapsedSeconds: session.elapsedSeconds,
                        distanceMeters: session.distanceMeters,
                        heartRate: nil
                    )
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

#Preview {
    NavigationStack { RunView(startImmediately: false) }
        .environment(AuthService())
        .environmentObject(WatchConnectivityService())
        .modelContainer(for: Run.self, inMemory: true)
}
