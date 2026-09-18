//
//  HomeView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/24/26.
//

import SwiftUI
import SwiftData
import MapKit

struct RunnerHomeView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        NavigationStack {
            HomeContent(ownerID: auth.userID)
                // 홈엔 타이틀이 없는데도 빈 내비게이션 바가 상단을 차지한다.
                // 숨기면 그만큼 최근 러닝 스크롤 영역이 늘어난다. 푸시된 화면은 자기 바를 그대로 쓴다.
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// 현재 계정의 기록만 조회 (ownerID 필터)
private struct HomeContent: View {
    @Query private var runs: [Run]
    private let ownerID: UUID?

    // 상수 바인딩이면 첫 렌더에 위치가 없을 때 .automatic(전국 지도)에 고정되고 되돌아오지 못한다.
    // 상태로 들고 있어야 위치를 잡은 뒤 카메라가 따라간다.
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var locationManager = CLLocationManager()

    /// 내 위치 점을 레벨 색으로. RootTabView가 넣어 준다.
    @Environment(\.levelTier) private var tier

    init(ownerID: UUID?) {
        self.ownerID = ownerID
        let owner = ownerID ?? .noOwner
        _runs = Query(filter: #Predicate<Run> { $0.ownerID == owner }, sort: \Run.startedAt, order: .reverse)
    }

    private var todayMeters: Double {
        let cal = Calendar.current
        // 최신순 정렬이라 오늘 기록은 맨 앞에만 있다 — 전체를 훑지 않는다
        return runs.prefix { cal.isDateInToday($0.startedAt) }.reduce(0) { $0 + $1.distanceMeters }
    }

    private var totalMeters: Double { runs.reduce(0) { $0 + $1.distanceMeters } }

    private var weekMeters: Double {
        StatsEngine.summary(runs: runs.map(\.badgeRun), period: .week).totalMeters
    }

    var body: some View {
        VStack(spacing: 0) {
            // 프로필·오늘 지도·시작 버튼은 항상 보이게 두고,
            // 스크롤은 아래의 최근 기록 영역에서만 일어난다.
            VStack(spacing: 24) {
                ProfileHeader(totalMeters: totalMeters, weekMeters: weekMeters)
                heroCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView {
                recentRunsSection
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            // 3개 고정이라 보통은 다 보이지만, 작은 기기(SE)나 큰 글씨에선 넘친다.
            // 스크롤은 남기되 다 보일 때는 튕기지 않게 한다.
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// 오늘 기록의 경로. 오늘 안 뛰었으면 빈 배열이라 지도는 현재 위치를 보여준다.
    /// runs 는 최신순이라 맨 앞만 보면 된다.
    private var todayRoute: [RoutePoint] {
        guard let latest = runs.first, Calendar.current.isDateInToday(latest.startedAt) else { return [] }
        return latest.route
    }

    /// 지도가 카드 전체를 채우고 그 위에 오늘 거리와 시작 버튼만 얹는다.
    /// 상자를 셋(지도·버튼·기록) 두면 화면이 빽빽해 보여서 하나로 합쳤다.
    /// 높이는 예전(지도 196 + 간격 24 + 버튼 56)과 같아 최근 러닝 3개가 그대로 다 보인다.
    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            mapLayer
                // 좌하단 Apple 지도 표기를 가리면 안 된다 — 버튼 높이만큼 안전 영역을 줘서 위로 올린다.
                .safeAreaPadding(.bottom, Self.mapOrnamentInset)

            LinearGradient(colors: [.clear, Color(.systemBackground).opacity(0.95)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("오늘의 러닝")
                        .font(.headline)
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(RunMath.formatKm(todayMeters))
                            .font(.system(size: 52, weight: .bold))
                            .monospacedDigit()
                        Text("km")
                            .foregroundStyle(.secondary)
                    }
                }
                startRunButton
            }
            .padding(16)
        }
        .frame(height: 276)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// 버튼(56) + 아래 패딩(16) + 여유(4)
    private static let mapOrnamentInset: CGFloat = 76

    /// 오늘 뛴 경로가 있으면 그 경로를, 없으면 현재 위치를.
    @ViewBuilder
    private var mapLayer: some View {
        if todayRoute.count > 1 {
            RouteMapView(route: todayRoute, showsLegend: false)
        } else {
            Map(position: $camera, interactionModes: []) {
                UserAnnotation()
            }
            .task {
                // 권한을 러닝 시작 때만 물어서, 한 번도 안 뛴 계정은 홈 지도가 권한 없이 뜬다.
                // 그러면 .userLocation 이 해석되지 못하고 .automatic(전국 지도)으로 떨어진다.
                if locationManager.authorizationStatus == .notDetermined {
                    locationManager.requestWhenInUseAuthorization()
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControlVisibility(.hidden)
            // 탭 틴트가 primary라 내 위치 점이 검게 나온다. 여기서만 레벨 색으로 되돌린다.
            // 블랙 레벨은 accent가 primary라 다크 모드에서도 묻히지 않는다.
            .tint(tier?.accent ?? .primary)
        }
    }

    private var startRunButton: some View {
        NavigationLink {
            RunView(startImmediately: true)
        } label: {
            PrimaryButtonLabel(title: "러닝 시작", systemImage: "figure.run")
        }
    }

    private var recentRunsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("최근 러닝")
                    .font(.headline)
                Spacer()
                if !runs.isEmpty {
                    NavigationLink {
                        RunListView(ownerID: ownerID)
                    } label: {
                        Text("전체 보기")
                            .font(.subheadline)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }
            }

            if runs.isEmpty {
                Text("아직 기록이 없어요. 첫 러닝을 시작해 보세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                ForEach(runs.prefix(3)) { run in
                    NavigationLink {
                        RunDetailView(run: run)
                    } label: {
                        RunHistoryRow(run: run)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - 최근 러닝 한 줄

struct RunHistoryRow: View {
    let run: Run

    var body: some View {
        HStack {
            Image(systemName: "figure.run")

            VStack(alignment: .leading) {
                Text("\(RunMath.formatKm(run.distanceMeters)) km")
                    .accessibilityIdentifier("runHistoryDistance")
                    .fontWeight(.semibold)

                // 기기 언어가 영어여도 "9월 6일" — 한국어 전용 앱이라 로케일을 고정
                Text("\(RunMath.formatDuration(run.movingSeconds)) · \(RunMath.formatPace(run.paceSecondsPerKm)) · \(run.startedAt.formatted(.dateTime.month().day().locale(Locale(identifier: "ko_KR"))))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding()
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    RunnerHomeView()
        .environment(AuthService())
        .modelContainer(for: Run.self, inMemory: true)
}
