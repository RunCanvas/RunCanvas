import SwiftUI
import SwiftData
import UIKit

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
    /// 이 화면이 직접 시작한 러닝만 구간 타이머로 쓴다 — 홈에서 켜 둔 러닝의 시간을 읽으면
    /// 첫 틱에 '훈련 완료'가 찍히고, 결과 화면을 닫고 나가는 길에 onAppear가 다시 돌아도 재시작하지 않는다
    @State private var didStart = false
    @State private var showsBusy = false
    @State private var showsLocationDenied = false
    @State private var showsNoOwner = false
    @State private var confirmsFinish = false
    @State private var awaitsLocationPermission = false
    @State private var healthAuthorizationMessage: String?

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
                    // 달리기와 걷기를 글자만으로 구분하면, 뛰면서 흔들리는 화면에서 잘 안 읽힌다
                    Image(systemName: progress.step.kind.isRunning ? "figure.run" : "figure.walk")
                        .font(.system(size: 34, weight: .semibold))
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
            .padding(.horizontal, 20)

            controls
                .padding(.horizontal, 20)
                .padding(.top, 20)

            Spacer().frame(height: 30)
        }
        .background(Color(.systemBackground))
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        // 남의 러닝(홈에서 시작한 것)이 돌고 있을 땐 뒤로가기를 남겨 둔다 — 여기서 막다른 길이 되면 안 된다
        .navigationBarBackButtonHidden(didStart && (run.state == .running || run.state == .paused))
        .onAppear(perform: startIfPossible)
        .onReceive(ticker) { _ in tick() }
        .onChange(of: run.locationAuthorization) { _, status in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                if awaitsLocationPermission { startIfPossible() }
            case .denied, .restricted:
                awaitsLocationPermission = false
                showsLocationDenied = true
            default: break
            }
        }
        .confirmationDialog("러닝을 종료할까요?", isPresented: $confirmsFinish, titleVisibility: .visible) {
            Button("종료", role: .destructive) { finish() }
            Button("취소", role: .cancel) {}
        }
        .alert("진행 중인 러닝이 있어요", isPresented: $showsBusy) {
            Button("확인", role: .cancel) { dismiss() }
        } message: {
            Text("진행 중인 러닝을 먼저 끝낸 뒤 훈련을 시작해 주세요.")
        }
        .alert("위치 권한이 필요해요", isPresented: $showsLocationDenied) {
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                dismiss()
            }
            Button("취소", role: .cancel) { dismiss() }
        } message: {
            Text("위치 접근이 꺼져 있어 거리가 기록되지 않아요. 설정에서 위치 권한을 허용한 뒤 다시 시작해 주세요.")
        }
        .alert("로그인이 필요해요", isPresented: $showsNoOwner) {
            // 나가야 한다 — 훈련 중에는 뒤로가기가 숨겨져 있고 finish() 는 계속 false 라,
            // 여기서 닫지 않으면 알럿만 다시 뜨는 막다른 길이 된다(앱을 강제 종료해야 한다).
            Button("확인", role: .cancel) { dismiss() }
        } message: {
            Text("로그인 정보를 찾지 못해 기록을 저장할 수 없어요. 다시 로그인한 뒤 저장해 주세요.")
        }
        .alert("기록을 저장하지 않았어요", isPresented: $runs.showsDiscardedRun) {
            Button("확인") { dismiss() }
        } message: {
            Text("이동 거리가 50m 이하인 러닝은 저장하지 않아요.")
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
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    /// RunView와 같은 조작감: 일시정지·재개는 PrimaryButton(레벨 컬러), 끝내기는 그 아래 작은 빨간 글자.
    /// 같은 크기로 나란히 두면 달리며 흔들리는 손이 일시정지 대신 끝내기를 눌러 세션이 날아간다.
    private var controls: some View {
        VStack(spacing: 16) {
            PrimaryButton(
                title: run.state == .paused ? "재개" : "일시정지",
                systemImage: run.state == .paused ? "figure.run" : "pause.fill"
            ) {
                if run.state == .paused { runs.resume() } else { runs.pause() }
            }
            Button { confirmsFinish = true } label: {
                Text(didFinish ? "저장하고 나가기" : "훈련 끝내기")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .frame(minWidth: 44, minHeight: 44)   // RunView 종료 버튼과 같은 탭 영역
                    .contentShape(Rectangle())
            }
        }
    }

    /// 진입 검사는 RunView.startRun과 같다. 훈련 화면엔 '시작' 버튼이 없어 막히면 바로 나간다.
    private func startIfPossible() {
        guard !didStart else { return }
        // finish는 이 값이 없으면 저장하지 않는다 — RunView를 한 번도 안 열었으면 비어 있다
        if let ownerID { runs.ownerID = ownerID }
        // 진행 중인 러닝 위에 훈련을 얹으면 그 러닝의 시간·거리가 훈련 기록이 되고, 끝내기가 그 러닝을 끝낸다
        guard run.state == .idle || run.state == .finished else { showsBusy = true; return }
        switch run.locationAuthorization {
        case .denied, .restricted:
            showsLocationDenied = true      // 권한이 없으면 시작하지 않는다 — 0.00km 훈련을 저장하게 두지 않기 위해
        case .notDetermined:
            awaitsLocationPermission = true
            run.requestLocationPermission()
        default:
            awaitsLocationPermission = false
            guard runs.start() else { showsNoOwner = true; return }
            didStart = true
            Task { await requestHealthAuthorization() }
        }
    }

    /// 매초: 흐른 시간을 러닝 세션에서 가져오고(일시정지가 그대로 반영된다) 구간이 바뀌면 한 번 알린다
    private func tick() {
        guard didStart, run.state == .running else { return }
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
        guard didStart else { return }
        if !runs.finish(sendToWatch: true) { showsNoOwner = true }
    }

    private func requestHealthAuthorization() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestSkipHealth") { return }
        #endif
        do {
            try await run.requestHealthAuthorization()
            run.restartHeartRateStream()
        } catch {
            // 왜: HealthKit 오류는 영어 시스템 문장이라 한국어 알럿에 그대로 노출하면 읽히지 않는다
            healthAuthorizationMessage = "설정 > 건강 > 데이터 접근 및 기기에서 RunCanvas를 켜면 심박이 기록돼요."
        }
    }
}
