import SwiftUI

/// 마라톤·러닝 이벤트 일정. 종류·거리·지역으로 거르고, 카드를 누르면 신청 페이지로 간다.
/// 카드 톤(회색 카드 + 16 라운드 + 20 여백)은 레벨·뱃지 화면과 같게 둔다.
struct MarathonScheduleView: View {
    @State private var service = MarathonService()
    @State private var category: MarathonCategory = .all
    @State private var course: MarathonCourse = .any
    @State private var region = KoreaRegion.all

    private var sections: [MarathonSchedule.MonthSection] {
        MarathonSchedule(events: service.events)
            .sections(category: category, course: course, region: region)
    }

    var body: some View {
        VStack(spacing: 0) {
            filters
            Divider()
            schedule
        }
        .background(Color(.systemBackground))
        .navigationTitle("마라톤 일정")
        .navigationBarTitleDisplayMode(.inline)
        .task { await service.load() }
    }

    // MARK: 목록

    private var schedule: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                if let notice = service.fallbackNotice {
                    Label(notice, systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 16))
                }

                if sections.isEmpty { placeholder }

                ForEach(sections) { section in
                    Section {
                        ForEach(section.events) { event in
                            MarathonCard(event: event)
                        }
                    } header: {
                        monthHeader(for: section)
                    }
                }

                Text("출처: kormarathon.com\n일정은 주최 측 사정으로 바뀔 수 있어요. 신청 전 공식 공지를 확인해 주세요.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(20)
        }
        .refreshable { await service.load() }
    }

    /// 앱이 한국어 전용이라 기기 로케일에 맡기지 않는다 ("September 2026" 대신 "2026년 9월")
    private func monthHeader(for section: MarathonSchedule.MonthSection) -> some View {
        let title: String
        if let start = section.monthStart {
            let parts = MarathonSchedule.calendar.dateComponents([.year, .month], from: start)
            title = "\(parts.year ?? 0)년 \(parts.month ?? 0)월"
        } else {
            title = "날짜 미정"
        }
        return HStack {
            Text(title).font(.headline)
            Spacer()
            Text("\(section.events.count)개")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .background(Color(.systemBackground))   // 스크롤할 때 카드가 제목 뒤로 비치지 않게
    }

    /// 필터 때문에 빈 것과 다가오는 일정이 정말 없는 것은 안내가 달라야 한다 —
    /// 오래된 캐시·씨앗은 전부 지난 날짜라 이때는 카테고리를 바꿔도 안 나온다
    private var isFiltering: Bool {
        category != .all || course != .any || region != KoreaRegion.all
    }

    private var placeholder: some View {
        ContentUnavailableView {
            Label(service.isLoading ? "불러오는 중" : (isFiltering ? "해당하는 일정이 없어요" : "다가오는 일정이 없어요"),
                  systemImage: "calendar")
        } description: {
            Text(service.isLoading ? "잠시만 기다려 주세요."
                 : (isFiltering ? "필터를 바꿔 보세요." : "아래로 당겨 새로 불러와 보세요."))
        } actions: {
            // 세 필터를 손으로 하나씩 되돌리게 하지 않는다
            if isFiltering, !service.isLoading {
                Button("필터 초기화") {
                    category = .all
                    course = .any
                    region = KoreaRegion.all
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    /// 지역 메뉴는 목록과 같은 필터(카테고리·거리·오늘 이후)를 거친 일정으로 만든다 —
    /// 지난 일정까지 세면 메뉴의 '서울 (12)' 와 실제 목록 9개가 어긋나고,
    /// 현재 카테고리에 0건인 지역이 메뉴에 남아 눌러도 빈 화면인 항목이 생긴다
    private var regionPool: [MarathonEvent] {
        MarathonSchedule(events: service.events)
            .sections(category: category, course: course)
            .flatMap(\.events)
    }

    private var regionCounts: [String: Int] {
        let pool = regionPool
        var counts = Dictionary(grouping: pool.compactMap(\.region), by: { $0 }).mapValues(\.count)
        counts[KoreaRegion.all] = pool.count
        return counts
    }

    // MARK: 카테고리 칩

    /// 두 줄로 끝낸다. 지역은 17개라 칩으로 깔면 가로 스크롤이 화면을 두 번 넘게 지나간다 → 메뉴 알약.
    private var filters: some View {
        VStack(spacing: 0) {   // 거리 칩 히트 영역(44pt)의 위쪽 6pt 가 줄 간격 노릇을 한다
            ChipRow(titles: MarathonCategory.allCases.map(\.rawValue), selected: category.rawValue) {
                category = MarathonCategory(rawValue: $0) ?? .all
            }
            // 알약은 스크롤 밖에 고정한다 — 한 줄에 다 넣으면 폭이 460pt 라 390pt 기기에서
            // 거리 칩을 고르는 순간 알약이 화면 밖으로 밀려 어느 지역으로 걸러졌는지 안 보인다
            HStack(spacing: 7) {
                FilterMenuPill(title: "지역",
                               // 고른 지역이 현재 카테고리에 0건이어도 메뉴에 남겨 되돌릴 수 있게 한다
                               options: KoreaRegion.chips(regions: regionPool.map(\.region) + [region]),
                               allOption: KoreaRegion.all,
                               counts: regionCounts,
                               selection: $region)
                Divider().frame(height: 18)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(MarathonCourse.allCases) { item in
                            chip(item.rawValue, isOn: course == item) { course = item }
                        }
                    }
                    .padding(.trailing, 20)
                }
            }
            .padding(.leading, 20)
        }
        .padding(.top, 10)
        .padding(.bottom, 4)   // 거리 칩 히트 영역 아래 6pt 가 이미 여백이라 보이는 간격은 10 그대로
    }

    /// 거리 칩 — `ChipRow` 는 한 줄을 통째로 쓰므로, 알약과 같은 줄에 놓으려고 낱개로 그린다
    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(isOn ? Color.primary : Color.card, in: Capsule())
                .foregroundStyle(isOn ? Color(.systemBackground) : .primary)
                // 보이는 칩은 32pt 그대로, 손가락이 닿는 영역만 44pt 로
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

}

// MARK: - 대회 카드

private struct MarathonCard: View {
    let event: MarathonEvent
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = event.signupURL { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                poster
                details
            }
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(event.signupURL == nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint(event.signupURL == nil ? ""
                           : (event.isAcceptingSignups ? "신청 페이지 열기" : "대회 페이지 열기"))
    }

    /// 포스터. 없는 대회도 있어서 자리는 항상 같은 높이로 두고 비었을 때만 다르게 채운다 —
    /// 카드 높이가 들쭉날쭉하면 목록이 지저분해 보인다.
    private var poster: some View {
        ZStack(alignment: .topLeading) {
            AsyncImage(url: event.imageURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Color.primary.opacity(0.06)
                    Image(systemName: "figure.run")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)   // 카드가 자식을 합쳐 읽어 '달리는 사람' 이 섞인다
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .clipped()

            HStack(alignment: .top) {
                HStack(spacing: 6) {
                    if let countdown {
                        chip(countdown.text, filled: false).accessibilityLabel(countdown.spoken)
                    }
                    if event.isAcceptingSignups { chip("접수 중", filled: true) }
                }
                Spacer(minLength: 0)
                // 야간·기부·펫·풀코스는 고르는 이유가 되는 정보라 카드에서 바로 보이게 한다.
                // 칩 줄을 하나 더 만들면 필터가 네 줄이 되므로 포스터 위에 얹는다
                HStack(spacing: 6) {
                    ForEach(event.tags.prefix(2), id: \.self) { tag in
                        chip(tag, filled: false)
                    }
                }
            }
            .padding(12)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(event.name)
                .font(.headline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            // 날짜는 항상 한 줄, 장소는 두 줄까지 — 한 줄에 같이 두면 SE·큰 글씨에서 장소가
            // 열두 자쯤에서 잘리는데 상세 화면이 없어 앱 안에서는 끝까지 읽을 곳이 없다
            VStack(alignment: .leading, spacing: 2) {
                Text(dateText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if !placeText.isEmpty {
                    Text(placeText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !courseTitles.isEmpty {
                HStack(spacing: 6) {
                    ForEach(courseTitles, id: \.self) { title in
                        Text(title)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemBackground), in: Capsule())
                    }
                }
            }

            if footerText != nil || event.signupURL != nil {
                HStack(spacing: 4) {
                    if let footerText {
                        Text(footerText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if event.signupURL != nil {
                        Text(linkText)
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                }
                .padding(.top, 1)
            }
        }
        .padding(16)
    }

    private func chip(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                // 포스터 위라 배경 밝기를 알 수 없다 → 채운 칩은 흑백 대비로, 나머지는 블러로 깐다
                if filled { Capsule().fill(Color.primary) } else { Capsule().fill(.ultraThinMaterial) }
            }
            .foregroundStyle(filled ? Color(.systemBackground) : .primary)
    }

    // MARK: 표시용 문자열

    /// "9월 19일 (토)" — 날짜 미정이면 그렇게 적는다
    private var dateText: String {
        guard let date = event.date else { return "날짜 미정" }
        let calendar = MarathonSchedule.calendar
        let parts = calendar.dateComponents([.month, .day, .weekday], from: date)
        let weekday = ["일", "월", "화", "수", "목", "금", "토"][(parts.weekday ?? 1) - 1]
        return "\(parts.month ?? 0)월 \(parts.day ?? 0)일 (\(weekday))"
    }

    /// 칩에는 "D-13", VoiceOver 에는 "13일 남음" — 'D-13' 은 '디 13' 으로 읽혀 뜻이 안 통한다
    private var countdown: (text: String, spoken: String)? {
        guard let days = event.daysAway() else { return nil }
        return switch days {
        case 0: (text: "오늘", spoken: "오늘")
        case 1: (text: "내일", spoken: "내일")
        default: (text: "D-\(days)", spoken: "\(days)일 남음")
        }
    }

    /// 마감된 대회까지 '신청' 으로 안내하면 눌러 봐야 마감인 걸 안다 — 접수 중일 때만 '신청'.
    /// 링크 자체는 마감 뒤에도 대회 소개 페이지라 살려 두고 이름만 바꾼다
    private var linkText: String {
        if event.isAcceptingSignups { return "신청" }
        return event.status == "closed" ? "접수 마감 · 자세히" : "자세히"
    }

    private var placeText: String {
        [event.region, event.place.isEmpty ? nil : event.place]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// 종목이 다섯 가지가 넘는 대회도 있다 — 카드가 밀리지 않게 네 개까지만.
    /// 원본은 'Half'·'Full' 영어인데 바로 위 필터 칩은 '하프'·'풀' 이라 표시만 맞춘다
    /// (동기화 스크립트에서 바꾸면 이미 받은 캐시는 영어로 남는다)
    private var courseTitles: [String] {
        let courses = event.courses.map { ["Half": "하프", "Full": "풀"][$0] ?? $0 }
        guard courses.count > 4 else { return courses }
        return courses.prefix(3) + ["+\(courses.count - 3)"]
    }

    private var footerText: String? {
        var parts: [String] = []
        if let deadline = event.registrationEnd, event.isAcceptingSignups {
            let d = MarathonSchedule.calendar.dateComponents([.month, .day], from: deadline)
            parts.append("신청 \(d.month ?? 0)월 \(d.day ?? 0)일 마감")
        }
        if let fee = event.feeMin {
            parts.append("\(fee.formatted())원부터")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack { MarathonScheduleView() }
}
