import SwiftUI

/// 레벨 · 최고 기록 · 뱃지 (NRC "업적" 화면 방식)
struct BadgesView: View {
    let runs: [BadgeRun]

    private var level: Level { Level.forTotalDistance(BadgeEngine.totalDistance(runs)) }
    private var earned: Set<Badge> { BadgeEngine.earned(runs: runs) }
    private var bests: PersonalBests { BadgeEngine.personalBests(runs) }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LevelCard(level: level)

                personalBests

                ForEach(Badge.Category.allCases) { category in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(category.rawValue)
                                .font(.headline)
                            Spacer()
                            Text("\(earnedCount(in: category))/\(Badge.allCases.filter { $0.category == category }.count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(Badge.allCases.filter { $0.category == category }) { badge in
                                BadgeCell(badge: badge, isEarned: earned.contains(badge), progress: BadgeEngine.progressValue(for: badge, runs: runs))
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("레벨과 뱃지")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func earnedCount(in category: Badge.Category) -> Int {
        earned.filter { $0.category == category }.count
    }

    private var personalBests: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("최고 기록")
                .font(.headline)
            HStack(spacing: 12) {
                BestTile(title: "최장 거리", value: RunMath.formatKm(bests.longestRunMeters), unit: "km")
                BestTile(title: "최고 페이스", value: RunMath.formatPace(bests.bestPaceSecondsPerKm), unit: "/km")
                BestTile(title: "최장 연속", value: "\(bests.longestStreakDays)", unit: "일")
            }
        }
    }
}

// MARK: - 레벨 카드

struct LevelCard: View {
    let level: Level

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Circle()
                    .fill(level.tier.color)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text("\(level.number)")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(level.tier.foreground)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(level.title) 레벨")
                        .font(.title3.weight(.semibold))
                    Text("누적 \(RunMath.formatKm(level.totalMeters)) km")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ProgressView(value: level.progress)
                .tint(level.tier.color)

            if let next = level.nextTier, let remaining = level.remainingMeters {
                Text("\(next.title) 레벨까지 \(RunMath.formatKm(remaining)) km")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("최고 레벨이에요")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 최고 기록 타일

private struct BestTile: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - 뱃지 셀

struct BadgeCell: View {
    let badge: Badge
    let isEarned: Bool
    let progress: Double

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isEarned ? Color.primary : Color.gray.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: badge.symbolName)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(isEarned ? Color(.systemBackground) : Color.gray.opacity(0.6))
            }
            Text(badge.title)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(isEarned ? badge.detail : progressText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 28, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .opacity(isEarned ? 1 : 0.85)
    }

    /// 잠긴 뱃지의 진행도: "3/7일", "6.0/50km", "3/10회"
    private var progressText: String {
        switch badge.category {
        case .distance, .total:
            "\(RunMath.formatKm(min(progress, badge.target)))/\(RunMath.formatKm(badge.target).replacingOccurrences(of: ".00", with: "")) km"
        case .streak:
            "\(Int(progress))/\(Int(badge.target))일"
        case .count:
            "\(Int(progress))/\(Int(badge.target))회"
        case .time:
            badge.detail
        }
    }
}

// MARK: - 레벨 색상 (NRC 팔레트)

extension Level.Tier {
    var color: Color {
        switch self {
        case .yellow: Color(red: 0.96, green: 0.77, blue: 0.09)
        case .orange: Color(red: 0.95, green: 0.42, blue: 0.11)
        case .green: Color(red: 0.18, green: 0.72, blue: 0.30)
        case .blue: Color(red: 0.12, green: 0.44, blue: 0.91)
        case .purple: Color(red: 0.48, green: 0.24, blue: 0.91)
        case .black: Color(red: 0.07, green: 0.07, blue: 0.07)
        case .volt: Color(red: 0.81, green: 1.0, blue: 0.0)
        }
    }

    /// 배경색 위 글자색
    var foreground: Color {
        switch self {
        case .yellow, .volt: .black
        default: .white
        }
    }
}

// MARK: - Preview (샘플 기록)

#Preview("기록 있음") {
    let cal = Calendar.current
    let runs: [BadgeRun] = (0..<14).map { i in
        BadgeRun(
            startedAt: cal.date(byAdding: .day, value: -i, to: .now)!,
            distanceMeters: [3_200, 5_400, 10_200, 7_100][i % 4],
            movingSeconds: [1_100, 1_800, 3_300, 2_400][i % 4]
        )
    }
    NavigationStack { BadgesView(runs: runs) }
}

#Preview("기록 없음") {
    NavigationStack { BadgesView(runs: []) }
}
