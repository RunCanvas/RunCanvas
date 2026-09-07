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
    /// 따라뛰기로 들어왔으면 그 코스. 평소 러닝은 nil
    var course: Course? = nil

    @Environment(AuthService.self) private var auth
    @Environment(RunCoordinator.self) private var runs
    @EnvironmentObject private var watchConnectivity: WatchConnectivityService
    @Environment(\.dismiss) private var dismiss
    @State private var healthAuthorizationMessage: String?
    @State private var showsLocationDenied = false
    @State private var showsNoOwner = false
    @State private var confirmsFinish = false
    /// 위치 권한 프롬프트에 답하길 기다리는 중 — 허용되면 onChange에서 시작한다
    @State private var awaitsLocationPermission = false
    @State private var recovered: RecoveredRun?
    @State private var courseProgress: Double = 0
    @State private var offCourseMeters: Double = 0
    @State private var warnedOffCourse = false

    private var session: RunSession { runs.session }

    /// 따라뛰기 상태 표시 — 얼마나 왔는지, 코스에서 벗어났는지
    private func courseStrip(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(course.name, systemImage: "map")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(Int(courseProgress * 100))%")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            ProgressView(value: courseProgress)
                .tint(.primary)
            Text(offCourseMeters > 50
                 ? "코스에서 \(Int(offCourseMeters))m 벗어났어요"
                 : String(format: "코스 %.2f km 중 %.2f km", course.distanceKm, course.distanceKm * courseProgress))
                .font(.caption)
                .foregroundStyle(offCourseMeters > 50 ? .red : .secondary)
                .monospacedDigit()
        }
        .padding(14)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
    }

    /// 위치가 갱신될 때만 다시 계산한다 — body가 그려질 때마다 하면 경로 전체를 초당 몇 번씩 훑는다
    private func updateCourseFollow() {
        guard let course, let last = session.route.last else { return }
        let point = CoursePoint(last)
        courseProgress = CourseGeometry.progress(at: point, in: course.path)
        offCourseMeters = CourseGeometry.offCourseMeters(point, path: course.path)
        if offCourseMeters > 50, !warnedOffCourse {
            warnedOffCourse = true            // 벗어난 동안 계속 떠들지 않게 한 번만
            session.announce("코스에서 벗어났어요")
        } else if offCourseMeters < 25 {
            warnedOffCourse = false
        }
    }
    private var isActive: Bool { session.state == .running || session.state == .paused }

    private var locationDenied: Bool {
        session.locationAuthorization == .denied || session.locationAuthorization == .restricted
    }

    /// 실제로 누가 기록 중인지 — 러닝 중엔 연결 여부가 아니라 세션 상태를 따른다
    private var recordsOnWatch: Bool {
        isActive ? session.healthManagedExternally : watchConnectivity.isReachable
    }

    var body: some View {
        @Bindable var runs = runs

        VStack(spacing: 0) {
            if let course {
                courseStrip(course)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            Spacer()

            VStack(spacing: 8) {
                Text("거리").font(.subheadline).foregroundStyle(.secondary)
                Text(RunMath.formatKm(session.distanceMeters)).font(.system(size: 64, weight: .bold))
                Text("km").font(.title3).foregroundStyle(.secondary)
                // 첫 유효 fix 전엔 0.00에 시간만 흘러 GPS 탓인지 앱 탓인지 알 수 없다 — 경로 점이 들어오면 사라진다
                if isActive, session.route.isEmpty {
                    Text(locationDenied ? "위치 권한이 꺼져 있어 거리가 기록되지 않아요" : "GPS 신호를 찾는 중…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isActive,
                   !session.healthManagedExternally,
                   watchConnectivity.isWatchAppInstalled,
                   !watchConnectivity.isReachable {
                    Text("Watch로 심박을 기록하려면 워치 앱을 먼저 열어 주세요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                case .idle, .finished: startRun()
                case .running: runs.pause()
                case .paused: runs.resume()
                }
            }
            .padding(.horizontal, 20)

            if isActive {
                // 종료는 되돌릴 수 없는데 일시정지 바로 아래에 있다 — 흔들리는 손이 잘못 눌러도 확인 한 번은 거친다
                Button { confirmsFinish = true } label: {
                    Text("러닝 종료")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .frame(minWidth: 44, minHeight: 44)   // 글자 높이(약 20pt)만으로는 탭 영역이 너무 작다
                        .contentShape(Rectangle())
                }
                .padding(.top, 4)
            }

            Spacer().frame(height: 30)
        }
        .navigationTitle("러닝")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Label(
                    recordsOnWatch ? "Watch 기록" : "iPhone 기록",
                    systemImage: recordsOnWatch ? "applewatch.radiowaves.left.and.right" : "iphone"
                )
                .labelStyle(.titleAndIcon)   // 내비바에선 기본이 아이콘만이라 글자가 사라진다
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationBarBackButtonHidden(isActive)
        .onChange(of: session.route.count) { _, _ in updateCourseFollow() }
        .onChange(of: session.locationAuthorization) { _, status in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                if awaitsLocationPermission { startRun() }
            case .denied, .restricted:
                awaitsLocationPermission = false
                showsLocationDenied = true
            default: break
            }
        }
        .onAppear {
            if let id = auth.userID { runs.ownerID = id }
            if session.state == .idle || session.state == .finished { recovered = RunSession.recoverable() }
            // 중단 러닝 알럿이 뜰 상황이면 저장/버리기를 고른 뒤에 시작한다
            if startImmediately,
               session.state == .idle || session.state == .finished,
               recovered == nil { startRun() }
        }
        .confirmationDialog("러닝을 종료할까요?", isPresented: $confirmsFinish, titleVisibility: .visible) {
            Button("종료", role: .destructive) { finish() }
            Button("취소", role: .cancel) {}
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
            // 달리는 중에 권한이 꺼진 경우엔 "다시 시작"이 할 수 있는 답이 아니다 — 지금 기록이 어떻게 되는지를 알린다
            Text(isActive
                 ? "위치 접근이 꺼져 있어 지금부터 거리가 쌓이지 않아요. 종료하면 여기까지만 저장돼요."
                 : "위치 접근이 꺼져 있어 거리가 기록되지 않아요. 설정에서 위치 권한을 허용한 뒤 다시 시작해 주세요.")
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
                // 홈에서 '러닝 시작'을 눌러 왔다 — 알럿에 답한 뒤 같은 버튼을 또 누르게 하지 않는다
                if startImmediately, !showsNoOwner { startRun() }
            }
            Button("버리기", role: .destructive) {
                RunSession.discardRecoverable()
                recovered = nil
                if startImmediately { startRun() }
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
        // 언제 것인지 모르면 저장할지 판단할 수 없다. 날짜는 기기 로케일에 맡기지 않고 한국어로 고정
        let startedAt = recovered.startedAt.formatted(
            .dateTime.month().day().hour().minute().locale(Locale(identifier: "ko_KR"))
        )
        return "\(startedAt)에 시작한 \(RunMath.formatKm(recovered.distanceMeters))km를 저장할까요?"
    }

    private func startRun() {
        guard session.state == .idle || session.state == .finished else { return }
        switch session.locationAuthorization {
        case .denied, .restricted:
            showsLocationDenied = true      // 권한이 없으면 시작하지 않는다 — 0.00km를 저장하게 두지 않기 위해
        case .notDetermined:
            // 프롬프트를 읽는 동안 타이머가 돌지 않게 허용된 뒤(onChange)에 시작한다.
            // 거부하면 시작 자체가 안 되니 0.00km 러닝이 생기지 않는다
            awaitsLocationPermission = true
            session.requestLocationPermission()
        default:
            awaitsLocationPermission = false
            guard runs.start() else {
                showsNoOwner = true
                return
            }
            // 시작이 먼저다. 건강 권한 시트가 떠 있는 동안 GPS 기록이 멈춰 있으면,
            // 사용자는 "시작을 눌렀는데 아무 일도 안 일어나는" 앱을 보게 된다.
            // 위치 권한이 결정된 뒤라 첫 러닝에 시스템 알럿 두 개가 겹치지도 않는다.
            Task { await requestHealthAuthorization() }
        }
    }

    /// 러닝을 시작한 화면에서 한 번만 — 화면에 다시 들어올 때마다 스트림을 다시 걸면
    /// 앵커 없는 쿼리가 시작 이후 심박을 전부 다시 배달해 평균이 앞 구간으로 쏠린다
    private func requestHealthAuthorization() async {
        #if DEBUG
        // UI 테스트에서는 건강 권한 시트를 띄우지 않는다 — 시스템 시트가 러닝 화면을 덮어
        // 종료 버튼을 누를 수 없고, 시트 자동화는 로케일·OS 버전마다 깨진다.
        if ProcessInfo.processInfo.arguments.contains("-uiTestSkipHealth") { return }
        #endif
        do {
            try await session.requestHealthAuthorization()
            session.restartHeartRateStream()   // 권한이 늦게 와도 심박을 놓치지 않게
        } catch {
            healthAuthorizationMessage = error.localizedDescription
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
