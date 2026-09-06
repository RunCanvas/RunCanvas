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
    private static let log = Logger(subsystem: "name.dongharyu.RunCanvas", category: "marathon")
    private static let cacheName = "marathon-cache.json"

    private(set) var events: [MarathonEvent] = []
    private(set) var isLoading = false
    /// 서버를 못 읽어 캐시·씨앗으로 보여주는 중이면 채워진다
    private(set) var fallbackNotice: String?

    /// 서버 → 캐시 → 번들 씨앗
    @MainActor
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let today = Self.dayFormatter.string(from: .now)
            let rows: [MarathonEvent] = try await supabase
                .from("marathon_events")
                .select("name,event_date,region,place,courses,type,tags,status,reg_end_date,fee_min,signup_url")
                // 날짜 미정(null)도 함께 가져온다
                .or("event_date.gte.\(today),event_date.is.null")
                .order("event_date", ascending: true)
                .execute()
                .value
            guard !rows.isEmpty else { throw LoadError.empty }
            events = rows
            fallbackNotice = nil
            cache(rows)
        } catch {
            Self.log.error("마라톤 일정 서버 조회 실패: \(error.localizedDescription, privacy: .public)")
            loadFallback()
        }
    }

    private enum LoadError: Error { case empty }

    private func loadFallback() {
        if let cached = Self.readCache(), !cached.isEmpty {
            events = cached
            fallbackNotice = "저장해 둔 목록을 보여주고 있어요. 연결되면 최신으로 바뀝니다."
            return
        }
        let seeded = MarathonSchedule.bundled().events
        events = seeded
        fallbackNotice = seeded.isEmpty
            ? "일정을 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
            : "앱에 담아 둔 목록을 보여주고 있어요. 연결되면 최신으로 바뀝니다."
    }

    // MARK: 캐시

    private func cache(_ rows: [MarathonEvent]) {
        guard let url = Self.cacheURL,
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
    }
}
