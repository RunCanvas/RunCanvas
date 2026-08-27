//
//  RunStatsView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/25/26.
//

import SwiftUI
import SwiftData
import Charts

struct RunStatsView: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        NavigationStack {
            StatsContent(ownerID: auth.userID)
        }
    }
}

/// 현재 계정의 기록만 (ownerID 필터)
private struct StatsContent: View {
    @Query private var runs: [Run]
    @AppStorage("weeklyTargetDistance") private var weeklyTargetKm: Double = 20
    @State private var period: StatsEngine.Period = .week
    @Environment(\.levelTier) private var tier
    private let ownerID: UUID?

    init(ownerID: UUID?) {
        self.ownerID = ownerID
        let owner = ownerID ?? UUID()
        _runs = Query(filter: #Predicate<Run> { $0.ownerID == owner }, sort: \Run.startedAt, order: .reverse)
    }

    private var badgeRuns: [BadgeRun] { runs.map(\.badgeRun) }
    private var bests: PersonalBests { BadgeEngine.personalBests(badgeRuns) }
    private var summary: StatsEngine.Summary { StatsEngine.summary(runs: badgeRuns, period: period) }
    private var buckets: [StatsEngine.Bucket] { StatsEngine.buckets(runs: badgeRuns, period: period) }
    private var weekMeters: Double { StatsEngine.summary(runs: badgeRuns, period: .week).totalMeters }

    var body: some View {
        ScrollView {
            if runs.isEmpty {
                ContentUnavailableView("아직 기록이 없어요", systemImage: "figure.run",
                                       description: Text("첫 러닝을 마치면 여기에 통계가 쌓여요"))
                    .padding(.top, 80)
            } else {
                VStack(spacing: 24) {
                    overallSection
                    periodSection
                    weeklyGoalSection
                    recentSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle("러닝 통계")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 전체 기록

    private var overallSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("전체 기록")
                .font(.headline)

            HStack(spacing: 12) {
                StatCard(title: "총 거리", value: RunMath.formatKm(bests.totalMeters), unit: "km")
                StatCard(title: "러닝 횟수", value: "\(bests.totalRuns)", unit: "회")
            }
            HStack(spacing: 12) {
                StatCard(title: "평균 페이스", value: RunMath.formatPace(overallPace), unit: "/km")
                StatCard(title: "최장 거리", value: RunMath.formatKm(bests.longestRunMeters), unit: "km")
            }
        }
    }

    private var overallPace: Double? {
        RunMath.paceSecondsPerKm(distanceMeters: bests.totalMeters, seconds: badgeRuns.reduce(0) { $0 + $1.movingSeconds })
    }

    // MARK: - 기간별 (주/월/년 차트)

    private var periodSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("기간별")
                    .font(.headline)
                Spacer()
                Picker("기간", selection: $period) {
                    ForEach(StatsEngine.Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            VStack(spacing: 18) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(RunMath.formatKm(summary.totalMeters))
                        .font(.system(size: 40, weight: .bold))
                    Text("km")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(periodTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Chart(buckets) { bucket in
                    BarMark(x: .value("기간", bucket.label), y: .value("km", bucket.distanceMeters / 1000))
                        .foregroundStyle(tier?.accent ?? Color.primary)
                        .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: axisLabels) { _ in
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                        AxisGridLine()
                        AxisValueLabel()
                    }
                }
                .frame(height: 150)

                HStack {
                    StatLabel(title: "횟수", value: "\(summary.count)회")
                    StatLabel(title: "평균 페이스", value: RunMath.formatPace(summary.avgPaceSecondsPerKm))
                    StatLabel(title: "시간", value: RunMath.formatDuration(summary.totalSeconds))
                }
            }
            .padding(20)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var periodTitle: String {
        switch period {
        case .week: "이번 주"
        case .month: Date.now.formatted(.dateTime.month(.wide))
        case .year: Date.now.formatted(.dateTime.year())
        }
    }

    /// 월은 31개라 5일 간격만 표시
    private var axisLabels: [String] {
        period == .month ? buckets.filter { $0.id % 5 == 0 }.map(\.label) : buckets.map(\.label)
    }

    // MARK: - 이번 주 목표 (설정의 주간 목표 거리)

    private var weeklyGoalSection: some View {
        let targetMeters = weeklyTargetKm * 1000
        let fraction = targetMeters > 0 ? min(weekMeters / targetMeters, 1) : 0
        return VStack(alignment: .leading, spacing: 16) {
            Text("이번 주")
                .font(.headline)

            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("주간 목표")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(RunMath.formatKm(targetMeters)) km")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("달성 거리")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(RunMath.formatKm(weekMeters)) km")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                }

                VStack(spacing: 8) {
                    ProgressView(value: fraction)
                    HStack {
                        Text("\(Int(fraction * 100))% 달성")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(weekMeters >= targetMeters ? "목표 달성!" : "\(RunMath.formatKm(targetMeters - weekMeters)) km 남음")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - 최근 기록

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("최근 러닝")
                    .font(.headline)
                Spacer()
                NavigationLink("전체 보기") {
                    RunListView(ownerID: ownerID)
                }
                .font(.subheadline)
            }

            ForEach(runs.prefix(3)) { run in
                NavigationLink {
                    RunDetailView(run: run)
                } label: {
                    RunStatHistoryRow(
                        date: run.startedAt.formatted(.dateTime.month().day()),
                        distance: "\(RunMath.formatKm(run.distanceMeters)) km",
                        time: RunMath.formatDuration(run.movingSeconds),
                        pace: RunMath.formatPace(run.paceSecondsPerKm)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 통계 카드

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 최근 러닝 기록

struct RunStatHistoryRow: View {
    let date: String
    let distance: String
    let time: String
    let pace: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(distance)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 6) {
                Text(time)
                    .font(.subheadline)
                
                Text("\(pace) /km")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
        }
        .padding(16)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    RunStatsView()
        .environment(AuthService())
        .modelContainer(for: Run.self, inMemory: true)
}
