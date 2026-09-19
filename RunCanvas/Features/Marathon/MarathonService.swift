import Foundation
import Observation
import Supabase
import OSLog

/// 마라톤 일정을 서버(Supabase `marathon_events`)에서 받아 온다.
///
/// 일정을 앱에 박아 두면 하나 바꿀 때마다 앱 심사를 다시 받아야 해서 데이터는 서버에 둔다.
/// 서버 → 로컬 캐시 → 번들 씨앗 순으로 물러나므로 비행기 모드에서도 목록이 빈 채로 남지 않는다.
@Observable
final class MarathonService {
    private static let log = Logger(subsystem: "com.daun1997.RunCanvas", category: "marathon")
    private static let cacheName = "marathon-cache.json"

    @ObservationIgnored private let fetchEvents: () async throws -> [MarathonEvent]
    @ObservationIgnored private let readCachedEvents: () -> [MarathonEvent]?
    @ObservationIgnored private let readBundledEvents: () -> [MarathonEvent]
    @ObservationIgnored private let storeCachedEvents: ([MarathonEvent]) -> Void
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    private(set) var events: [MarathonEvent] = []
    /// 첫 렌더에서 '다가오는 일정이 없어요'가 번쩍이지 않게 로딩으로 시작한다 (CourseService 와 같은 이유)
    private(set) var isLoading = true
    /// 서버를 못 읽어 캐시·씨앗으로 보여주는 중이면 채워진다
    private(set) var fallbackNotice: String?

    init(
        fetchEvents: (() async throws -> [MarathonEvent])? = nil,
        readCachedEvents: (() -> [MarathonEvent]?)? = nil,
        readBundledEvents: (() -> [MarathonEvent])? = nil,
        storeCachedEvents: (([MarathonEvent]) -> Void)? = nil
    ) {
        self.fetchEvents = fetchEvents ?? Self.fetchFromServer
        self.readCachedEvents = readCachedEvents ?? Self.readCache
        self.readBundledEvents = readBundledEvents ?? { MarathonSchedule.bundled().events }
        self.storeCachedEvents = storeCachedEvents ?? Self.cache
    }

    /// 서버 → 캐시 → 번들 씨앗
    @MainActor
    func load() async {
        // 첫 로드 중 당겨서 새로고침해도 즉시 끝내지 않고 같은 조회가 끝날 때까지 기다린다.
        if let loadTask {
            await loadTask.value
            return
        }

        isLoading = true
        showQuickFallback()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshFromServer()
        }
        loadTask = task
        await task.value
        loadTask = nil
        isLoading = false
    }

    /// 캐시·씨앗을 먼저 그려 느린 네트워크에서도 빈 화면이 생기지 않게 한다.
    @MainActor
    private func showQuickFallback() {
        guard events.isEmpty else { return }
        if let cached = readCachedEvents(), !cached.isEmpty {
            events = cached
            return
        }
        let bundled = readBundledEvents()
        if !bundled.isEmpty { events = bundled }
    }

    @MainActor
    private func refreshFromServer() async {
        do {
            let rows = try await fetchEvents()
            guard !rows.isEmpty else { throw LoadError.empty }
            events = rows
            fallbackNotice = nil
            storeCachedEvents(rows)
        } catch {
            Self.log.error("마라톤 일정 서버 조회 실패: \(error.localizedDescription, privacy: .public)")
            loadFallback()
        }
    }

    private static func fetchFromServer() async throws -> [MarathonEvent] {
        let today = dayFormatter.string(from: .now)
        return try await supabase
            .from("marathon_events")
            .select("name,event_date,region,place,courses,type,tags,status,reg_end_date,fee_min,signup_url,image_url")
            // 날짜 미정(null)도 함께 가져온다
            .or("event_date.gte.\(today),event_date.is.null")
            .order("event_date", ascending: true)
            .execute()
            .value
    }

    private enum LoadError: Error { case empty }

    private func loadFallback() {
        if let cached = readCachedEvents(), !cached.isEmpty {
            events = cached
            fallbackNotice = "저장해 둔 목록을 보여주고 있어요. 아래로 당기면 다시 불러와요."
            return
        }
        let seeded = readBundledEvents()
        events = seeded
        fallbackNotice = seeded.isEmpty
            ? "일정을 불러오지 못했어요. 아래로 당겨 다시 불러와 주세요."
            : "앱에 담아 둔 목록을 보여주고 있어요. 아래로 당기면 다시 불러와요."
    }

    // MARK: 캐시

    private static func cache(_ rows: [MarathonEvent]) {
        guard let url = cacheURL,
              let data = try? JSONEncoder().encode(rows.map(CachedEvent.init)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func readCache() -> [MarathonEvent]? {
        guard let url = cacheURL, let data = try? Data(contentsOf: url) else { return nil }
        return MarathonSchedule.parseEvents(data)
    }

    private static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(cacheName)
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// 캐시는 서버와 같은 키로 적어 둔다 — 읽을 때 같은 디코더를 그대로 쓰기 위해
private struct CachedEvent: Encodable {
    let name: String
    let event_date: String?
    let region: String?
    let place: String
    let courses: [String]
    let type: String
    let tags: [String]
    let status: String?
    let reg_end_date: String?
    let fee_min: Int?
    let signup_url: String?
    let image_url: String?

    init(_ event: MarathonEvent) {
        name = event.name
        event_date = event.date.map(MarathonService.dayFormatter.string(from:))
        region = event.region
        place = event.place
        courses = event.courses
        type = event.kind
        tags = event.tags
        status = event.status
        reg_end_date = event.registrationEnd.map(MarathonService.dayFormatter.string(from:))
        fee_min = event.feeMin
        signup_url = event.signupURL?.absoluteString
        image_url = event.imageURL?.absoluteString
    }
}
