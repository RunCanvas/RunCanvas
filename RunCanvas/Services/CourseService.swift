import Foundation
import Observation
import Supabase
import OSLog

/// 공유 코스 목록·등록·삭제. 서버(`courses`)가 원본이고 앱은 캐시하지 않는다 —
/// 남이 올린 코스라 언제든 지워질 수 있고, 목록은 들어올 때마다 새로 받으면 그만이다.
/// 목록 정렬 기준
enum CourseSort: String, CaseIterable, Identifiable, Hashable {
    case newest = "최신순"
    case shortest = "짧은 코스부터"
    case longest = "긴 코스부터"

    var id: String { rawValue }
    var column: String { self == .newest ? "created_at" : "distance_m" }
    var ascending: Bool { self == .shortest }
}

@Observable
final class CourseService {
    private static let log = Logger(subsystem: "com.daun1997.RunCanvas", category: "course")
    private static let pageSize = 50

    private struct Filter: Equatable {
        let region: String
        let sort: CourseSort
        let mineOnly: Bool
        let ownerID: UUID?
    }

    private(set) var courses: [Course] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var totalCount = 0
    /// 서버를 못 읽었을 때 화면에 보여줄 한 줄
    private(set) var failureNotice: String?
    /// 지역별 코스 개수 — 칩에 붙여서 "눌러도 빈 화면"인 지역을 미리 알려 준다
    private(set) var regionCounts: [String: Int] = [:]
    private var activeFilter: Filter?
    private var loadGeneration = 0
    private var countGeneration = 0

    var hasMore: Bool { courses.count < totalCount }

    /// 지역·내 코스 필터는 목록·다음 페이지가 똑같이 걸어야 한다 — 한 곳에서 만든다.
    private func query(for filter: Filter) -> PostgrestFilterBuilder {
        var query = supabase.from("courses").select(count: .exact)
        if filter.region != KoreaRegion.all { query = query.eq("region", value: filter.region) }
        if filter.mineOnly, let ownerID = filter.ownerID {
            query = query.eq("owner_id", value: ownerID.uuidString)
        }
        return query
    }

    /// 늦게 도착한 응답인지. 세대가 밀렸으면 새 요청이 상태를 쥐고 있으므로 아무것도 건드리지 않는다.
    private func isStale(_ generation: Int, filter: Filter? = nil) -> Bool {
        generation != loadGeneration || (filter.map { activeFilter != $0 } ?? false)
    }

    @MainActor
    func load(region: String = KoreaRegion.all, sort: CourseSort = .newest,
              mineOnly: Bool = false, ownerID: UUID? = nil) async {
        let filter = Filter(region: region, sort: sort, mineOnly: mineOnly, ownerID: ownerID)
        loadGeneration += 1
        let requestGeneration = loadGeneration
        activeFilter = filter
        isLoading = true
        isLoadingMore = false
        failureNotice = nil
        do {
            let response: PostgrestResponse<[Course]> = try await query(for: filter)
                .order(sort.column, ascending: sort.ascending)
                // 같은 거리·시각인 행도 순서가 고정돼야 offset 페이지에서 빠지거나 겹치지 않는다.
                .order("id", ascending: true)
                // 한 코스가 경로 점 수백 개를 들고 온다 — 200개를 받으면 목록 한 번에 메가바이트 단위가 된다
                .range(from: 0, to: Self.pageSize - 1)
                .execute()
            if isStale(requestGeneration) { return }
            if Task.isCancelled { isLoading = false; return }
            courses = response.value
            totalCount = response.count ?? response.value.count
            failureNotice = nil
        } catch {
            if isStale(requestGeneration) { return }
            if Task.isCancelled { isLoading = false; return }
            Self.log.error("코스 목록 실패: \(error.localizedDescription, privacy: .public)")
            courses = []
            totalCount = 0
            failureNotice = "코스를 불러오지 못했어요. 연결을 확인해 주세요."
        }
        isLoading = false
    }

    /// 현재 필터의 다음 50개를 이어 붙인다. 필터가 바뀌면 세대가 달라져 늦은 응답은 버린다.
    @MainActor
    func loadMore() async {
        guard !isLoading, !isLoadingMore, hasMore, let filter = activeFilter else { return }
        let requestGeneration = loadGeneration
        let start = courses.count
        isLoadingMore = true
        failureNotice = nil
        do {
            let response: PostgrestResponse<[Course]> = try await query(for: filter)
                .order(filter.sort.column, ascending: filter.sort.ascending)
                .order("id", ascending: true)
                .range(from: start, to: start + Self.pageSize - 1)
                .execute()
            if isStale(requestGeneration, filter: filter) { return }
            if Task.isCancelled { isLoadingMore = false; return }
            let existing = Set(courses.map(\.id))
            courses.append(contentsOf: response.value.filter { !existing.contains($0.id) })
            totalCount = response.count ?? max(totalCount, courses.count)
        } catch {
            if isStale(requestGeneration, filter: filter) { return }
            if Task.isCancelled { isLoadingMore = false; return }
            Self.log.error("코스 다음 페이지 실패: \(error.localizedDescription, privacy: .public)")
            failureNotice = "코스를 더 불러오지 못했어요. 잠시 후 다시 시도해 주세요."
        }
        isLoadingMore = false
    }

    /// 지역 칩에 붙일 개수. 경로는 빼고 지역 문자열만 받아서 가볍다.
    @MainActor
    func loadRegionCounts(mineOnly: Bool = false, ownerID: UUID? = nil) async {
        struct RegionRow: Decodable { let region: String }
        countGeneration += 1
        let requestGeneration = countGeneration
        do {
            var query = supabase.from("courses").select("region", count: .exact)
            if mineOnly, let ownerID { query = query.eq("owner_id", value: ownerID.uuidString) }
            let response: PostgrestResponse<[RegionRow]> = try await query.limit(1_000).execute()
            guard requestGeneration == countGeneration, !Task.isCancelled else { return }
            let rows = response.value
            var counts = Dictionary(grouping: rows.map(\.region), by: { $0 }).mapValues(\.count)
            counts[KoreaRegion.all] = response.count ?? rows.count
            regionCounts = counts
        } catch {
            guard requestGeneration == countGeneration, !Task.isCancelled else { return }
            Self.log.error("지역별 개수 실패: \(error.localizedDescription, privacy: .public)")
            regionCounts = [:]      // 개수를 못 세면 칩에 아무것도 안 붙인다
        }
    }

    /// 기록 하나를 코스로 올린다. 경로 앞뒤는 등록 화면에서 이미 잘라 넘긴다(집·직장 노출 방지).
    @MainActor
    func register(path: [CoursePoint], name: String, region: String,
                  ownerID: UUID, ownerNickname: String) async throws -> Course {
        guard path.count >= 2 else { throw CourseError.tooShort }   // 서버 courses_path_size 하한과 같게
        // 서버 제약과 같은 기준(점 5000개·100km). 여기서 막지 않으면 업로드가 400 으로 튕겨
        // 사용자에게는 "연결을 확인해 주세요"로 보인다
        let distance = CourseGeometry.length(path)
        guard path.count <= CourseGeometry.maxPathPoints, distance <= 100_000 else { throw CourseError.tooLong }

        let course = Course(ownerID: ownerID, ownerNickname: ownerNickname,
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            region: region,
                            distanceMeters: CourseGeometry.length(path),
                            path: path)
        try await supabase.from("courses").insert(course).execute()
        courses.insert(course, at: 0)
        totalCount += 1
        return course
    }

    @MainActor
    func delete(_ course: Course) async throws {
        try await supabase.from("courses").delete().eq("id", value: course.id.uuidString).execute()
        let wasLoaded = courses.contains { $0.id == course.id }
        courses.removeAll { $0.id == course.id }
        if wasLoaded {
            totalCount = max(0, totalCount - 1)
            regionCounts[course.region] = max(0, (regionCounts[course.region] ?? 1) - 1)
            regionCounts[KoreaRegion.all] = max(0, (regionCounts[KoreaRegion.all] ?? 1) - 1)
        }
    }

    enum CourseError: LocalizedError {
        case tooShort
        case tooLong

        var errorDescription: String? {
            switch self {
            case .tooShort:
                // 앞뒤 150m를 자르므로, 짧은 기록은 자르고 나면 코스라 할 게 안 남는다
                "코스로 올리기엔 기록이 짧아요. 600m 이상 달린 기록을 골라 주세요."
            case .tooLong:
                // 서버가 courses_distance·courses_path_size 로 막는다 — 그 전에 이유를 알려 준다
                "코스로 올리기엔 기록이 길어요. 100km 이하 기록을 골라 주세요."
            }
        }
    }
}
