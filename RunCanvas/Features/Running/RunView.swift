//
//  RunView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/24/26.
//

import SwiftUI
import SwiftData
import UIKit

/// 러닝 중 화면: 거리·시간·페이스·BPM, 시작/일시정지/재개, 종료 → 결과 화면
/// 세션과 워치 콜백은 RunCoordinator(앱 수명)가 들고 있고 이 화면은 상태만 그린다.
struct RunView: View {
    let startImmediately: Bool

    @Environment(AuthService.self) private var auth
    @Environment(RunCoordinator.self) private var runs
    @EnvironmentObject private var watchConnectivity: WatchConnectivityService
    @Environment(\.dismiss) private var dismiss
    @State private var didRequestHealthAuthorization = false
    @State private var healthAuthorizationMessage: String?
    @State private var showsLocationDenied = false
    @State private var showsNoOwner = false
    @State private var recovered: RecoveredRun?

    private var session: RunSession { runs.session }
    private var isActive: Bool { session.state == .running || session.state == .paused }

    /// 실제로 누가 기록 중인지 — 러닝 중엔 연결 여부가 아니라 세션 상태를 따른다
    private var recordsOnWatch: Bool {
        isActive ? session.healthManagedExternally : watchConnectivity.isReachable
    }

    var body: some View {
        @Bindable var runs = runs

        VStack(spacing: 0) {
            HStack {
                Text("러닝").font(.title2).bold()
                Spacer()
                Label(
                    recordsOnWatch ? "Watch 기록" : "iPhone 기록",
                    systemImage: recordsOnWatch ? "applewatch.radiowaves.left.and.right" : "iphone"
                )
                .font(.caption)
                .foregroundStyle(recordsOnWatch ? .green : .secondary)
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
                case .running: runs.pause()
                case .paused: runs.resume()
                case .finished: break
                }
            }
            .padding(.horizontal, 24)

            if isActive {
                Button("러닝 종료") { finish() }
                    .font(.subheadline).foregroundStyle(.red).padding(.top, 16)
            }

            Spacer().frame(height: 30)
        }
        .navigationBarBackButtonHidden(isActive)
        .task {
            guard !didRequestHealthAuthorization else { return }
            didRequestHealthAuthorization = true
            do {
                try await session.requestHealthAuthorization()
            } catch {
                healthAuthorizationMessage = error.localizedDescription
            }
            if startImmediately, session.state == .idle, recovered == nil {
                startRun()
            }
        }
        .onAppear {
            if let id = auth.userID { runs.ownerID = id }
            if session.state == .idle { recovered = RunSession.recoverable() }
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
        .alert(
            "기록 방식이 바뀌었어요",
            isPresented: Binding(
                get: { runs.takeoverMessage != nil },
                set: { if !$0 { runs.takeoverMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(runs.takeoverMessage ?? "")
        }
        .alert("위치 권한이 필요해요", isPresented: $showsLocationDenied) {
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("위치 접근이 꺼져 있어 거리가 기록되지 않아요. 설정에서 위치 권한을 허용한 뒤 다시 시작해 주세요.")
        }
        .alert("로그인이 필요해요", isPresented: $showsNoOwner) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("로그인 정보를 찾지 못해 기록을 저장할 수 없어요. 다시 로그인한 뒤 저장해 주세요.")
        }
        .alert(
            "이전 러닝이 중단됐어요",
            isPresented: Binding(get: { recovered != nil }, set: { if !$0 { recovered = nil } })
        ) {
            Button("저장") {
                if let recovered, !runs.saveRecovered(recovered) { showsNoOwner = true }
                recovered = nil
            }
            Button("버리기", role: .destructive) {
                RunSession.discardRecoverable()
                recovered = nil
            }
        } message: {
            Text(recoveredMessage)
        }
        .fullScreenCover(item: $runs.finishedRun, onDismiss: { dismiss() }) { run in
            RunResultView(run: run)
        }
    }

    private var recoveredMessage: String {
        guard let recovered else { return "" }
        return "\(RunMath.formatKm(recovered.distanceMeters))km를 저장할까요?"
    }

    private func startRun() {
        switch session.locationAuthorization {
        case .denied, .restricted:
            showsLocationDenied = true      // 권한이 없으면 시작하지 않는다 — 0.00km를 저장하게 두지 않기 위해
        default:
            runs.start()
        }
    }

    private func finish() {
        if !runs.finish(sendToWatch: true) { showsNoOwner = true }
    }
}

#Preview {
    let container = try! ModelContainer(for: Run.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let watch = WatchConnectivityService()
    return NavigationStack { RunView(startImmediately: false) }
        .environment(AuthService())
        .environmentObject(watch)
        .environment(RunCoordinator(watch: watch, context: container.mainContext, session: RunSession()))
        .modelContainer(container)
}
