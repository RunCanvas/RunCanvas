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
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
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
            let parts = Calendar.current.dateComponents([.year, .month], from: start)
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

    private var placeholder: some View {
        ContentUnavailableView {
            Label(service.isLoading ? "불러오는 중" : "해당하는 일정이 없어요", systemImage: "calendar")
        } description: {
            Text(service.isLoading ? "잠시만 기다려 주세요." : "카테고리를 바꿔 보세요.")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: 카테고리 칩

    private var filters: some View {
        VStack(spacing: 6) {
            ChipRow(titles: MarathonCategory.allCases.map(\.rawValue), selected: category.rawValue) {
                category = MarathonCategory(rawValue: $0) ?? .all
            }
            ChipRow(titles: MarathonCourse.allCases.map(\.rawValue), selected: course.rawValue) {
                course = MarathonCourse(rawValue: $0) ?? .any
            }
            ChipRow(titles: KoreaRegion.chips(regions: service.events.map(\.region)), selected: region) { region = $0 }
        }
        .padding(.vertical, 10)
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
        .accessibilityHint(event.signupURL == nil ? "" : "신청 페이지 열기")
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
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .clipped()

            HStack(alignment: .top) {
                HStack(spacing: 6) {
                    if let countdown { chip(countdown, filled: false) }
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

            HStack(spacing: 6) {
                Text(dateText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if !placeText.isEmpty {
                    Text("·").foregroundStyle(.tertiary)
                    Text(placeText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
                        Text("신청")
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
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
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.month, .day, .weekday], from: date)
        let weekday = ["일", "월", "화", "수", "목", "금", "토"][(parts.weekday ?? 1) - 1]
        return "\(parts.month ?? 0)월 \(parts.day ?? 0)일 (\(weekday))"
    }

    private var countdown: String? {
        guard let days = event.daysAway() else { return nil }
        return switch days {
        case 0: "오늘"
        case 1: "내일"
        default: "D-\(days)"
        }
    }

    private var placeText: String {
        [event.region, event.place.isEmpty ? nil : event.place]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// 종목이 다섯 가지가 넘는 대회도 있다 — 카드가 밀리지 않게 네 개까지만
    private var courseTitles: [String] {
        let courses = event.courses
        guard courses.count > 4 else { return courses }
        return courses.prefix(3) + ["+\(courses.count - 3)"]
    }

    private var footerText: String? {
        var parts: [String] = []
        if let deadline = event.registrationEnd, event.isAcceptingSignups {
            let d = Calendar.current.dateComponents([.month, .day], from: deadline)
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
