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
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userWeight") private var userWeight: Double = 60
    @State private var session = RunSession()
    @State private var finishedRun: Run?

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("러닝").font(.title2).bold(); Spacer() }
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
                case .idle: session.start()
                case .running: session.pause()
                case .paused: session.resume()
                case .finished: break
                }
            }
            .padding(.horizontal, 24)

            if session.state == .running || session.state == .paused {
                Button("러닝 종료") { finish() }
                    .font(.subheadline).foregroundStyle(.red).padding(.top, 16)
            }

            Spacer().frame(height: 30)
        }
        .navigationBarBackButtonHidden(session.state == .running || session.state == .paused)
        .onAppear { if startImmediately { session.start() } }
        .fullScreenCover(item: $finishedRun, onDismiss: { dismiss() }) { run in
            RunResultView(run: run)
        }
    }

    private func finish() {
        guard let ownerID = auth.userID else { return }
        finishedRun = session.finish(ownerID: ownerID, weightKg: userWeight, context: context)
    }
}

#Preview {
    NavigationStack { RunView(startImmediately: false) }
        .environment(AuthService())
        .modelContainer(for: Run.self, inMemory: true)
}
