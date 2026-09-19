import SwiftUI
import SwiftData

/// 레벨 · 챌린지 · 최고 기록 · 뱃지 (NRC 업적 + 스트라바 챌린지 방식). 현재 계정의 기록만 본다.
struct BadgesView: View {
    let ownerID: UUID?
    @Query private var storedRuns: [Run]
    @State private var earnedDates: [Badge: Date] = [:]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 로그인한 계정의 기록으로 계산
    init(ownerID: UUID?) {
        self.ownerID = ownerID
        let owner = ownerID ?? .noOwner
        _storedRuns = Query(filter: #Predicate<Run> { $0.ownerID == owner })
        // onAppear에서만 채우면 첫 프레임엔 설명 문구, 다음 프레임엔 날짜로 캡션이 한 번 바뀐다 — 저장된 값으로 시작
        _earnedDates = State(initialValue: ownerID.map(BadgeStore.earnedDates(for:)) ?? [:])
    }

    /// 프리뷰·테스트용: 기록을 직접 넣는다
    init(sampleRuns: [BadgeRun]) {
        self.ownerID = nil
        self.sampleRuns = sampleRuns
        _storedRuns = Query(filter: #Predicate<Run> { _ in false })
    }

    private var sampleRuns: [BadgeRun]? = nil
    private var runs: [BadgeRun] { sampleRuns ?? storedRuns.map(\.badgeRun) }

    /// 접근성 글자 크기에선 3열이 좁아 제목이 "하프 마라…"로 잘린다 — 2열로
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicTypeSize.isAccessibilitySize ? 2 : 3)
    }

    var body: some View {
        // 계산 프로퍼티로 두면 렌더 한 번에 수십 번 다시 돈다 — 여기서 한 번만 계산해 내려보낸다
        let badgeRuns = runs
        // BadgeStore가 진실(런꾸 스티커·서버 동기화와 같은 기준) — 기록을 지웠거나 다른 기기에서 딴 뱃지는 현재 기록으론 계산되지 않는다
        let earned = BadgeEngine.earned(runs: badgeRuns).union(earnedDates.keys)
        let bests = BadgeEngine.personalBests(badgeRuns)
        let level = Level.forTotalDistance(bests.totalMeters)
        let challenges = ChallengeEngine.statuses(runs: badgeRuns)
        // 뱃지 19개마다 전체 기록을 다시 훑으면 O(19×N) — 기록이 쌓인 계정에서 스크롤이 무거워진다
        let progresses = Dictionary(uniqueKeysWithValues: Badge.allCases.map {
            ($0, BadgeEngine.progressValue(for: $0, runs: badgeRuns))
        })

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LevelCard(level: level)

                challengeSection(challenges)

                personalBestsSection(bests)

                ForEach(Badge.Category.allCases) { category in
                    let inCategory = Badge.allCases.filter { $0.category == category }
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(category.rawValue)
                                .font(.headline)
                            Spacer()
                            Text("\(earned.filter { $0.category == category }.count)/\(inCategory.count)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(inCategory) { badge in
                                BadgeCell(
                                    badge: badge,
                                    isEarned: earned.contains(badge),
                                    earnedAt: earnedDates[badge],
                                    progress: progresses[badge] ?? 0
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
            guard let ownerID else { return }   // 로그인 전·프리뷰는 저장하지 않는다
            let badgeRuns = runs
            BadgeStore.recordNewlyEarned(from: badgeRuns, ownerID: ownerID)
            BadgeStore.recordCompletedChallenges(from: badgeRuns, ownerID: ownerID)
            earnedDates = BadgeStore.earnedDates(for: ownerID)
        }
    }

    // MARK: - 챌린지 (자동 참여, 이번 주·이번 달)

    private func challengeSection(_ challenges: [ChallengeEngine.Status]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
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

    private func personalBestsSection(_ bests: PersonalBests) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("최고 기록")
                .font(.headline)
            HStack(spacing: 12) {
                StatCard(title: "최장 거리", value: RunMath.formatKm(bests.longestRunMeters), unit: "km")
                StatCard(title: "최고 페이스", value: RunMath.formatPace(bests.bestPaceSecondsPerKm), unit: "/km")
                StatCard(title: "최장 연속", value: "\(bests.longestStreakDays)", unit: "일")
            }
            // 기록 탭(2열) 타일을 3열로 쓰면 "05'30\"" 같은 값이 넘친다 — 환경으로 내려가 StatCard 안 Text에 적용된다
            .lineLimit(1)
            .minimumScaleFactor(0.7)
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
                        Text("LV.\(level.number)")
                            .font(.subheadline.weight(.bold))
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
                .tint(level.tier.accent)
                .accessibilityLabel("\(level.title) 레벨 진행도")

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
        let value = min(status.value, c.target)   // 목표를 넘어도 "5 / 3회"처럼 보이지 않게
        return switch c.metric {
        case .totalDistance: "\(RunMath.formatKm(value)) / \(Int(c.target / 1000)) km"
        case .runCount: "\(Int(value)) / \(Int(c.target))회"
        case .longestRun: "최장 \(RunMath.formatKm(value)) km / \(Int(c.target / 1000)) km"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: status.isCompleted ? "checkmark.seal.fill" : (status.challenge.period == .week ? "calendar" : "calendar.badge.clock"))
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(status.isCompleted ? Color.primary : Color.secondary)
                .accessibilityHidden(true)   // 심볼 이름("Checkmark Seal")이 제목보다 먼저 읽히지 않게
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
        .accessibilityElement(children: .combine)   // 아이콘·제목·남은 일수·진행바·값이 5번 멈추지 않게 한 요소로
    }
}

// MARK: - 뱃지 셀

struct BadgeCell: View {
    let badge: Badge
    let isEarned: Bool
    var earnedAt: Date? = nil
    let progress: Double
    /// 고정 28pt면 큰 글씨에서 2줄 캡션이 프레임 밖으로 넘쳐 아래 행 그림과 겹친다
    @ScaledMetric(relativeTo: .caption2) private var captionHeight: CGFloat = 28

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
                .frame(height: captionHeight, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .opacity(isEarned ? 1 : 0.85)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isEarned ? "획득" : "잠김")
    }

    /// 획득: "2026. 08. 27. 획득" / 잠김: 진행도 "3/7일", "6.00/50.00 km", "3/10회"
    private var caption: String {
        if isEarned {
            // 기기 언어가 영어면 "08/27/2026"이 된다 — 한국어 전용 앱이라 로케일 고정
            if let earnedAt { return earnedAt.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).locale(Locale(identifier: "ko_KR"))) + " 획득" }
            return badge.detail
        }
        switch badge.category {
        case .distance, .total:
            // 첫 러닝은 target이 1회(거리 아님)라 거리 포맷을 쓰면 "0.00/0 km"가 된다
            if badge == .firstRun { return badge.detail }
            // 마라톤 42,195m를 Int(/1000)으로 자르면 42.00km에서 "42/42 km"인데 잠김이라 버그처럼 보인다
            return "\(RunMath.formatKm(min(progress, badge.target)))/\(RunMath.formatKm(badge.target)) km"
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
        Group {
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
        .accessibilityHidden(true)   // 그림은 옆·아래 제목이 설명한다 — 심볼 이름("Flag Checkered")이 읽히지 않게
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
        .modelContainer(for: Run.self, inMemory: true)   // sampleRuns여도 내부 @Query가 컨테이너를 요구한다
}

#Preview("기록 없음") {
    NavigationStack { BadgesView(sampleRuns: []) }
        .modelContainer(for: Run.self, inMemory: true)
}
