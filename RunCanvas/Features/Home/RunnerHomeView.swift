//
//  HomeView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/24/26.
//

import SwiftUI
import SwiftData

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

    init(ownerID: UUID?) {
        let owner = ownerID ?? UUID()
        _runs = Query(filter: #Predicate<Run> { $0.ownerID == owner }, sort: \Run.startedAt, order: .reverse)
    }

    private var todayMeters: Double {
        runs.filter { Calendar.current.isDateInToday($0.startedAt) }.reduce(0) { $0 + $1.distanceMeters }
    }

    var body: some View {
        VStack(spacing: 0) {

            // 상단 프로필
            ProfileHeader()
                .padding(.horizontal, 24)
                .padding(.top, 20)

            ScrollView {
                VStack(spacing: 28) {

                    // 오늘의 러닝
                    VStack(spacing: 12) {
                        Text("오늘의 러닝")
                            .font(.headline)

                        Text(RunMath.formatKm(todayMeters))
                            .font(.system(size: 52, weight: .bold))

                        Text("km")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    // 러닝 시작 버튼
                    NavigationLink {
                        RunView(startImmediately: true)
                    } label: {
                        HStack {
                            Image(systemName: "figure.run")
                            Text("러닝 시작")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // 최근 러닝
                    VStack(alignment: .leading, spacing: 16) {
                        Text("최근 러닝")
                            .font(.headline)

                        if runs.isEmpty {
                            Text("아직 기록이 없어요. 첫 러닝을 시작해 보세요.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
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
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
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
                    .fontWeight(.semibold)

                Text("\(RunMath.formatDuration(run.movingSeconds)) · \(RunMath.formatPace(run.paceSecondsPerKm)) · \(run.startedAt.formatted(.dateTime.month().day()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    RunnerHomeView()
        .environment(AuthService())
        .modelContainer(for: Run.self, inMemory: true)
}
