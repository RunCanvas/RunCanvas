import Foundation

/// 마라톤 대회·러닝 이벤트 하나.
/// 서버(Supabase `marathon_events`)와 번들 씨앗 JSON이 같은 키를 쓴다.
struct MarathonEvent: Identifiable, Equatable, Decodable {
    let name: String
    /// 날짜 미정이면 nil
    let date: Date?
    let region: String?
    let place: String
    /// "5km", "10km", "Half", "Full", "기타"
    let courses: [String]
    /// "대회" | "테마런"
    let kind: String
    let tags: [String]
    /// 원본 접수 상태 — open / closed / scheduled
    let status: String?
    let registrationEnd: Date?
    let feeMin: Int?
    let signupURL: URL?
    /// 대회 포스터 — 없는 대회도 있다
    let imageURL: URL?

    var id: String { "\(name)|\(date?.timeIntervalSince1970 ?? -1)" }

    private enum CodingKeys: String, CodingKey {
        case name, region, place, courses, tags, status
        case date = "event_date"
        case kind = "type"
        case registrationEnd = "reg_end_date"
        case feeMin = "fee_min"
        case signupURL = "signup_url"
        case imageURL = "image_url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        date = MarathonSchedule.parseDate(try? c.decode(String.self, forKey: .date))
        region = try? c.decode(String.self, forKey: .region)
        place = (try? c.decode(String.self, forKey: .place)) ?? ""
        courses = (try? c.decode([String].self, forKey: .courses)) ?? []
        kind = (try? c.decode(String.self, forKey: .kind)) ?? MarathonCategory.race.rawValue
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        status = try? c.decode(String.self, forKey: .status)
        registrationEnd = MarathonSchedule.parseDate(try? c.decode(String.self, forKey: .registrationEnd))
        feeMin = try? c.decode(Int.self, forKey: .feeMin)
        signupURL = (try? c.decode(String.self, forKey: .signupURL)).flatMap { URL(string: $0) }
        imageURL = (try? c.decode(String.self, forKey: .imageURL)).flatMap { URL(string: $0) }
    }

    init(name: String, date: Date?, region: String? = nil, place: String = "", courses: [String] = [],
         kind: String = "대회", tags: [String] = [], status: String? = nil,
         registrationEnd: Date? = nil, feeMin: Int? = nil, signupURL: URL? = nil, imageURL: URL? = nil) {
        self.name = name
        self.date = date
        self.region = region
        self.place = place
        self.courses = courses
        self.kind = kind
        self.tags = tags
        self.status = status
        self.registrationEnd = registrationEnd
        self.feeMin = feeMin
        self.signupURL = signupURL
        self.imageURL = imageURL
    }

    var isAcceptingSignups: Bool { status == "open" }

    /// 대회까지 남은 날. 오늘이면 0, 날짜 미정이면 nil
    func daysAway(now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let date else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: date)).day
    }

    /// 거리 카테고리 판정 — 원본 종목 문자열이 제각각("Half", "하프", "21.1km")이라 넓게 본다
    func hasCourse(_ course: MarathonCourse) -> Bool {
        courses.contains { course.matches($0) }
    }
}

/// 화면 상단 카테고리 칩
enum MarathonCategory: String, CaseIterable, Identifiable {
    case all = "전체"
    case race = "대회"
    case theme = "테마런"
    case open = "접수 중"

    var id: String { rawValue }

    func includes(_ event: MarathonEvent) -> Bool {
        switch self {
        case .all: true
        case .race: event.kind == MarathonCategory.race.rawValue
        case .theme: event.kind == MarathonCategory.theme.rawValue
        case .open: event.isAcceptingSignups
        }
    }
}

/// 거리 카테고리
enum MarathonCourse: String, CaseIterable, Identifiable {
    case any = "전체 거리"
    case short = "5km"
    case ten = "10km"
    case half = "하프"
    case full = "풀"

    var id: String { rawValue }

    func matches(_ raw: String) -> Bool {
        let text = raw.lowercased().replacingOccurrences(of: " ", with: "")
        switch self {
        case .any: return true
        case .short: return text.hasPrefix("5k") || text.hasPrefix("~5k") || text.hasPrefix("3") || text.hasPrefix("4")
        case .ten: return text.hasPrefix("10k")
        case .half: return text.contains("half") || text.contains("하프") || text.contains("21")
        case .full: return text.contains("full") || text.contains("풀") || text.contains("42")
        }
    }

    func includes(_ event: MarathonEvent) -> Bool {
        self == .any ? true : event.hasCourse(self)
    }
}

/// 지역 카테고리. 값은 서버가 준 문자열 그대로 쓰고(고정 enum 으로 두면 새 지역이 사라진다) 순서만 앱이 정한다.
/// 마라톤 일정과 공유 코스가 같은 칩을 쓴다.
enum KoreaRegion {
    static let all = "전체 지역"
    /// 가나다순이면 서울·경기가 한참 뒤로 밀린다 → 사람이 찾는 순서로
    static let order = ["서울", "경기", "인천", "강원", "충북", "충남", "대전", "세종",
                        "전북", "전남", "광주", "경북", "경남", "대구", "울산", "부산", "제주"]

    /// 목록에 실제로 있는 지역만 칩으로 만든다 — 눌러도 빈 화면인 칩을 두지 않는다
    static func chips(regions: [String?]) -> [String] {
        let found = Set(regions.compactMap { $0 }.filter { !$0.isEmpty })
        return [all] + order.filter(found.contains) + found.subtracting(order).sorted()
    }

    /// 행정구역 이름("서울특별시", "충청북도")을 앱이 쓰는 짧은 이름으로. 못 알아보면 nil.
    /// 코스를 올릴 때 지역을 손으로 고르게 하면 잘못 고른 코스가 섞인다 — 위치에서 먼저 추측한다.
    static func short(administrativeArea area: String) -> String? {
        let prefixes: [(String, String)] = [
            ("서울", "서울"), ("부산", "부산"), ("대구", "대구"), ("인천", "인천"), ("광주", "광주"),
            ("대전", "대전"), ("울산", "울산"), ("세종", "세종"), ("경기", "경기"), ("강원", "강원"),
            ("제주", "제주"), ("충청북", "충북"), ("충청남", "충남"), ("충북", "충북"), ("충남", "충남"),
            ("전라북", "전북"), ("전라남", "전남"), ("전북", "전북"), ("전남", "전남"),
            ("경상북", "경북"), ("경상남", "경남"), ("경북", "경북"), ("경남", "경남")
        ]
        return prefixes.first { area.hasPrefix($0.0) }?.1
    }

    static func includes(_ region: String, _ event: MarathonEvent) -> Bool {
        region == all || event.region == region
    }
}

/// 일정 묶음 + 필터링. 순수 함수라 유닛 테스트가 쉽다.
struct MarathonSchedule: Equatable, Decodable {
    var updatedAt: String = ""
    var events: [MarathonEvent] = []

    private enum CodingKeys: String, CodingKey { case updatedAt, events }

    init(updatedAt: String = "", events: [MarathonEvent] = []) {
        self.updatedAt = updatedAt
        self.events = events
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = (try? c.decode(String.self, forKey: .updatedAt)) ?? ""
        // 한 항목이 깨져도 나머지는 살린다
        var events: [MarathonEvent] = []
        if var list = try? c.nestedUnkeyedContainer(forKey: .events) {
            while !list.isAtEnd {
                if let event = try? list.decode(MarathonEvent.self) { events.append(event) }
                else { _ = try? list.decode(AnyIgnored.self) }
            }
        }
        self.events = events
    }

    struct MonthSection: Identifiable, Equatable {
        /// "2026-11" 또는 날짜 미정을 뜻하는 "tbd"
        let id: String
        let monthStart: Date?
        var events: [MarathonEvent]
    }

    /// 카테고리·거리·지역으로 거른 뒤 월별로 묶는다. 날짜 미정은 마지막.
    func sections(
        category: MarathonCategory = .all,
        course: MarathonCourse = .any,
        region: String = KoreaRegion.all,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [MonthSection] {
        let today = calendar.startOfDay(for: now)
        let filtered = events
            .filter { category.includes($0) && course.includes($0) && KoreaRegion.includes(region, $0) }
            .filter { $0.date.map { calendar.startOfDay(for: $0) >= today } ?? true }

        var dated: [String: [MarathonEvent]] = [:]
        var undated: [MarathonEvent] = []
        for event in filtered {
            guard let date = event.date else { undated.append(event); continue }
            let parts = calendar.dateComponents([.year, .month], from: date)
            dated[String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0), default: []].append(event)
        }

        var sections = dated.keys.sorted().map { key -> MonthSection in
            let sorted = dated[key]!.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
            return MonthSection(id: key, monthStart: sorted.first?.date.map { calendar.dateInterval(of: .month, for: $0)?.start ?? $0 }, events: sorted)
        }
        if !undated.isEmpty {
            sections.append(MonthSection(id: "tbd", monthStart: nil, events: undated.sorted { $0.name < $1.name }))
        }
        return sections
    }

    static func parseDate(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        return isoDay.date(from: String(text.prefix(10)))
    }

    private static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// 깨진 JSON이면 빈 일정 (크래시 없음)
    static func parse(_ data: Data) -> MarathonSchedule {
        (try? JSONDecoder().decode(MarathonSchedule.self, from: data)) ?? MarathonSchedule()
    }

    /// 서버가 돌려주는 건 배열 하나뿐이라 그것도 받아들인다
    static func parseEvents(_ data: Data) -> [MarathonEvent] {
        guard var list = try? JSONDecoder().decode([FailableEvent].self, from: data) else { return [] }
        list.removeAll { $0.value == nil }
        return list.compactMap(\.value)
    }

    /// 앱에 함께 넣어 둔 씨앗 — 서버를 못 읽을 때 쓴다
    static func bundled(bundle: Bundle = .main) -> MarathonSchedule {
        guard let url = bundle.url(forResource: "marathons", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return MarathonSchedule() }
        return parse(data)
    }
}

/// 배열 안 한 항목이 깨져도 나머지를 살리기 위한 래퍼
private struct FailableEvent: Decodable {
    let value: MarathonEvent?
    init(from decoder: Decoder) throws { value = try? MarathonEvent(from: decoder) }
}

private struct AnyIgnored: Decodable {}
