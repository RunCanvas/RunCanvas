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
                .toolbar {
                    // 툴바에 링크 두 개를 나란히 두면 제목이 밀린다 → 메뉴 하나로
                    Menu("더보기", systemImage: "ellipsis.circle") {
                        NavigationLink("마라톤 일정") { MarathonScheduleView() }
                        NavigationLink("러닝 코스") { CourseListView() }
                        NavigationLink("트레이닝") { TrainingProgramListView() }
                    }
                }
        }
    }
}

/// 현재 계정의 기록만 (ownerID 필터)
private struct StatsContent: View {
    @Query private var runs: [Run]
    @AppStorage("weeklyTargetDistance") private var weeklyTargetKm: Double = 20
    @State private var period: StatsEngine.Period = .week
    private let ownerID: UUID?

    init(ownerID: UUID?) {
        self.ownerID = ownerID
        let owner = ownerID ?? .noOwner
        _runs = Query(filter: #Predicate<Run> { $0.ownerID == owner }, sort: \Run.startedAt, order: .reverse)
    }

    var body: some View {
        // 계산 프로퍼티로 두면 렌더 한 번에 전체 배열을 열 몇 번씩 다시 훑는다 — 여기서 한 번만
        let badgeRuns = runs.map(\.badgeRun)
        let bests = BadgeEngine.personalBests(badgeRuns)
        let summary = StatsEngine.summary(runs: badgeRuns, period: period)
        let buckets = StatsEngine.buckets(runs: badgeRuns, period: period)
        let weekMeters = StatsEngine.summary(runs: badgeRuns, period: .week).totalMeters
        let overallPace = RunMath.paceSecondsPerKm(distanceMeters: bests.totalMeters,
                                                   seconds: badgeRuns.reduce(0) { $0 + $1.movingSeconds })

        ScrollView {
            if runs.isEmpty {
                ContentUnavailableView("아직 기록이 없어요", systemImage: "figure.run",
                                       description: Text("첫 러닝을 마치면 여기에 통계가 쌓여요"))
                    .padding(.top, 80)
            } else {
                VStack(spacing: 24) {
                    overallSection(bests, pace: overallPace)
                    periodSection(summary, buckets)
                    weeklyGoalSection(weekMeters)
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

    private func overallSection(_ bests: PersonalBests, pace: Double?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("전체 기록")
                .font(.headline)

            HStack(spacing: 12) {
                StatCard(title: "총 거리", value: RunMath.formatKm(bests.totalMeters), unit: "km")
                StatCard(title: "러닝 횟수", value: "\(bests.totalRuns)", unit: "회")
            }
            HStack(spacing: 12) {
                StatCard(title: "평균 페이스", value: RunMath.formatPace(pace), unit: "/km")
                StatCard(title: "최장 거리", value: RunMath.formatKm(bests.longestRunMeters), unit: "km")
            }
        }
    }

    // MARK: - 기간별 (주/월/년 차트)

    private func periodSection(_ summary: StatsEngine.Summary, _ buckets: [StatsEngine.Bucket]) -> some View {
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
                        .foregroundStyle(Color.primary)
                        .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: axisLabels(buckets)) { _ in
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
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var periodTitle: String {
        // 기기 언어·달력이 무엇이든 "9월"·"2026년" — 로케일만 바꾸면 불교력 기기에서 "2569년"이 나온다
        let parts = Calendar.appGregorian.dateComponents([.year, .month], from: .now)
        return switch period {
        case .week: "이번 주"
        case .month: "\(parts.month ?? 1)월"
        case .year: "\(parts.year ?? 0)년"
        }
    }

    /// 월은 31개라 1·5·10·…·30일만 표시 (id는 0부터라 +1 해서 달력 날짜 기준으로 거른다)
    private func axisLabels(_ buckets: [StatsEngine.Bucket]) -> [String] {
        period == .month ? buckets.filter { $0.id == 0 || ($0.id + 1) % 5 == 0 }.map(\.label) : buckets.map(\.label)
    }

    // MARK: - 이번 주 목표 (설정의 주간 목표 거리)

    private func weeklyGoalSection(_ weekMeters: Double) -> some View {
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
                        .tint(.primary)
                        .accessibilityLabel("주간 목표 달성률")
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
            .background(Color.card)
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
                NavigationLink {
                    RunListView(ownerID: ownerID)
                } label: {
                    // 글자 박스만 눌리면 44pt 미달 — 러닝 직후 손 떨릴 때도 눌리게 히트 영역 확보
                    Text("전체 보기")
                        .font(.subheadline)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
            }

            // 홈·전체 목록과 같은 행 — 같은 데이터가 화면마다 다르게 보이지 않게
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
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    RunStatsView()
        .environment(AuthService())
        .modelContainer(for: Run.self, inMemory: true)
}
