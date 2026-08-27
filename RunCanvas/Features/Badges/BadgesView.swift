import SwiftUI
import SwiftData

/// 레벨 · 챌린지 · 최고 기록 · 뱃지 (NRC 업적 + 스트라바 챌린지 방식). 현재 계정의 기록만 본다.
struct BadgesView: View {
    let ownerID: UUID
    @Query private var storedRuns: [Run]
    @State private var earnedDates: [Badge: Date] = [:]

    /// 로그인한 계정의 기록으로 계산
    init(ownerID: UUID?) {
        let owner = ownerID ?? UUID()
        self.ownerID = owner
        _storedRuns = Query(filter: #Predicate<Run> { $0.ownerID == owner })
    }

    /// 프리뷰·테스트용: 기록을 직접 넣는다
    init(sampleRuns: [BadgeRun]) {
        self.ownerID = UUID()
        self.sampleRuns = sampleRuns
        _storedRuns = Query(filter: #Predicate<Run> { _ in false })
    }

    private var sampleRuns: [BadgeRun]? = nil
    private var runs: [BadgeRun] { sampleRuns ?? storedRuns.map(\.badgeRun) }

    private var level: Level { Level.forTotalDistance(BadgeEngine.totalDistance(runs)) }
    private var earned: Set<Badge> { BadgeEngine.earned(runs: runs) }
    private var bests: PersonalBests { BadgeEngine.personalBests(runs) }
    private var challenges: [ChallengeEngine.Status] { ChallengeEngine.statuses(runs: runs) }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                LevelCard(level: level)

                challengeSection

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
                                BadgeCell(
                                    badge: badge,
                                    isEarned: earned.contains(badge),
                                    earnedAt: earnedDates[badge],
                                    progress: BadgeEngine.progressValue(for: badge, runs: runs)
                                )
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
        .navigationTitle("레벨과 뱃지")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 기록으로 계산된 뱃지·챌린지 중 아직 저장 안 된 것은 지금 날짜로 기록 (러닝 종료 화면을 안 거친 경우 대비)
            BadgeStore.recordNewlyEarned(from: runs, ownerID: ownerID)
            BadgeStore.recordCompletedChallenges(from: runs, ownerID: ownerID)
            earnedDates = BadgeStore.earnedDates(for: ownerID)
        }
    }

    private func earnedCount(in category: Badge.Category) -> Int {
        earned.filter { $0.category == category }.count
    }

    // MARK: - 챌린지 (자동 참여, 이번 주·이번 달)

    private var challengeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("챌린지")
                    .font(.headline)
                Spacer()
                Text("\(challenges.filter(\.isCompleted).count)/\(challenges.count) 완료")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(challenges.enumerated()), id: \.element.challenge.id) { index, status in
                    ChallengeRow(status: status)
                    if index < challenges.count - 1 { Divider().padding(.leading, 16) }
                }
            }
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
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
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 챌린지 행

private struct ChallengeRow: View {
    let status: ChallengeEngine.Status

    private var valueText: String {
        let c = status.challenge
        return switch c.metric {
        case .totalDistance: "\(RunMath.formatKm(min(status.value, c.target))) / \(Int(c.target / 1000)) km"
        case .runCount: "\(Int(status.value)) / \(Int(c.target))회"
        case .longestRun: "최장 \(RunMath.formatKm(status.value)) km / \(Int(c.target / 1000)) km"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: status.isCompleted ? "checkmark.seal.fill" : (status.challenge.period == .week ? "calendar" : "calendar.badge.clock"))
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(status.isCompleted ? Color.primary : Color.secondary)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(status.challenge.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(status.isCompleted ? "완료" : "\(status.daysLeft)일 남음")
                        .font(.caption)
                        .foregroundStyle(status.isCompleted ? Color.primary : Color.secondary)
                }
                ProgressView(value: status.fraction)
                    .tint(.primary)
                Text(valueText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
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
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - 뱃지 셀

struct BadgeCell: View {
    let badge: Badge
    let isEarned: Bool
    var earnedAt: Date? = nil
    let progress: Double

    var body: some View {
        VStack(spacing: 8) {
            BadgeArt(badge: badge, isEarned: isEarned, size: 72)
            Text(badge.title)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 28, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .opacity(isEarned ? 1 : 0.85)
    }

    /// 획득: "2026.08.27 획득" / 잠김: 진행도 "3/7일", "6.00/50 km", "3/10회"
    private var caption: String {
        if isEarned {
            if let earnedAt { return earnedAt.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)) + " 획득" }
            return badge.detail
        }
        switch badge.category {
        case .distance, .total:
            return "\(RunMath.formatKm(min(progress, badge.target)))/\(Int(badge.target / 1000)) km"
        case .streak:
            return "\(Int(progress))/\(Int(badge.target))일"
        case .count:
            return "\(Int(progress))/\(Int(badge.target))회"
        case .time:
            return badge.detail
        }
    }
}

/// 뱃지 그림: 에셋 일러스트(획득=컬러, 잠김=흑백 반투명). 일러스트가 없는 뱃지는 심볼 원으로.
struct BadgeArt: View {
    let badge: Badge
    let isEarned: Bool
    var size: CGFloat = 72

    var body: some View {
        if let ui = UIImage(named: badge.imageName) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .saturation(isEarned ? 1 : 0)
                .opacity(isEarned ? 1 : 0.5)
        } else {
            ZStack {
                Circle()
                    .fill(isEarned ? Color.primary : Color.gray.opacity(0.15))
                Image(systemName: badge.symbolName)
                    .font(.system(size: size * 0.39, weight: .semibold))
                    .foregroundStyle(isEarned ? Color(.systemBackground) : Color.gray.opacity(0.6))
            }
            .frame(width: size, height: size)
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
    NavigationStack { BadgesView(sampleRuns: runs) }
}

#Preview("기록 없음") {
    NavigationStack { BadgesView(sampleRuns: []) }
}
