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
    private static let log = Logger(subsystem: "name.dongharyu.RunCanvas", category: "course")
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
            var query = supabase.from("courses").select(count: .exact)
            if region != KoreaRegion.all { query = query.eq("region", value: region) }
            if mineOnly, let ownerID { query = query.eq("owner_id", value: ownerID.uuidString) }
            let response: PostgrestResponse<[Course]> = try await query
                .order(sort.column, ascending: sort.ascending)
                // 같은 거리·시각인 행도 순서가 고정돼야 offset 페이지에서 빠지거나 겹치지 않는다.
                .order("id", ascending: true)
                // 한 코스가 경로 점 수백 개를 들고 온다 — 200개를 받으면 목록 한 번에 메가바이트 단위가 된다
                .range(from: 0, to: Self.pageSize - 1)
                .execute()
            guard requestGeneration == loadGeneration else { return }
            guard !Task.isCancelled else {
                isLoading = false
                return
            }
            courses = response.value
            totalCount = response.count ?? response.value.count
            failureNotice = nil
        } catch {
            guard requestGeneration == loadGeneration else { return }
            guard !Task.isCancelled else {
                isLoading = false
                return
            }
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
            var query = supabase.from("courses").select(count: .exact)
            if filter.region != KoreaRegion.all { query = query.eq("region", value: filter.region) }
            if filter.mineOnly, let ownerID = filter.ownerID {
                query = query.eq("owner_id", value: ownerID.uuidString)
            }
            let response: PostgrestResponse<[Course]> = try await query
                .order(filter.sort.column, ascending: filter.sort.ascending)
                .order("id", ascending: true)
                .range(from: start, to: start + Self.pageSize - 1)
                .execute()
            guard requestGeneration == loadGeneration, activeFilter == filter else { return }
            guard !Task.isCancelled else {
                isLoadingMore = false
                return
            }
            let existing = Set(courses.map(\.id))
            courses.append(contentsOf: response.value.filter { !existing.contains($0.id) })
            totalCount = response.count ?? max(totalCount, courses.count)
        } catch {
            guard requestGeneration == loadGeneration, activeFilter == filter else { return }
            guard !Task.isCancelled else {
                isLoadingMore = false
                return
            }
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

    /// 기록 하나를 코스로 올린다. 경로 앞뒤는 잘라서 보낸다(집·직장 노출 방지).
    /// 자르고 남은 게 너무 짧으면 등록하지 않고 이유를 알려 준다.
    @MainActor
    func register(route: [RoutePoint], name: String, region: String,
                  ownerID: UUID, ownerNickname: String) async throws -> Course {
        let trimmed = CourseGeometry.trimmed(CourseGeometry.path(from: route))
        return try await register(path: trimmed, name: name, region: region,
                                  ownerID: ownerID, ownerNickname: ownerNickname)
    }

    /// 등록 화면에서 이미 계산한 공유 경로를 받아 검증과 업로드가 같은 결과를 쓰게 한다.
    @MainActor
    func register(path: [CoursePoint], name: String, region: String,
                  ownerID: UUID, ownerNickname: String) async throws -> Course {
        guard !path.isEmpty else { throw CourseError.tooShort }

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

        var errorDescription: String? {
            switch self {
            case .tooShort:
                // 앞뒤 150m를 자르므로, 짧은 기록은 자르고 나면 코스라 할 게 안 남는다
                "코스로 올리기엔 기록이 짧아요. 600m 이상 달린 기록을 골라 주세요."
            }
        }
    }
}
