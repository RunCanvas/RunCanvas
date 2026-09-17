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
        }
    }
}

/// 현재 계정의 기록만 조회 (ownerID 필터)
private struct HomeContent: View {
    @Query private var runs: [Run]
    private let ownerID: UUID?

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
            VStack(spacing: 20) {
                ProfileHeader(totalMeters: totalMeters, weekMeters: weekMeters)
                todayRunMap
                startRunButton
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
        }
    }

    private var todayRunMap: some View {
        ZStack(alignment: .bottomLeading) {
            Map(position: .constant(.userLocation(fallback: .automatic)), interactionModes: []) {
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControlVisibility(.hidden)

            LinearGradient(colors: [.clear, Color(.systemBackground).opacity(0.95)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                Text("오늘의 러닝")
                    .font(.headline)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(RunMath.formatKm(todayMeters))
                        .font(.system(size: 52, weight: .bold))
                    Text("km")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
