import Foundation
import Observation
import Supabase
import OSLog

/// 공유 코스 목록·등록·삭제. 서버(`courses`)가 원본이고 앱은 캐시하지 않는다 —
/// 남이 올린 코스라 언제든 지워질 수 있고, 목록은 들어올 때마다 새로 받으면 그만이다.
/// 목록 정렬 기준
enum CourseSort: String, CaseIterable, Identifiable {
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

    private(set) var courses: [Course] = []
    private(set) var isLoading = false
    /// 서버를 못 읽었을 때 화면에 보여줄 한 줄
    private(set) var failureNotice: String?
    /// 지역별 코스 개수 — 칩에 붙여서 "눌러도 빈 화면"인 지역을 미리 알려 준다
    private(set) var regionCounts: [String: Int] = [:]

    @MainActor
    func load(region: String = KoreaRegion.all, sort: CourseSort = .newest,
              mineOnly: Bool = false, ownerID: UUID? = nil) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var query = supabase.from("courses").select()
            if region != KoreaRegion.all { query = query.eq("region", value: region) }
            if mineOnly, let ownerID { query = query.eq("owner_id", value: ownerID.uuidString) }
            courses = try await query
                .order(sort.column, ascending: sort.ascending)
                // 한 코스가 경로 점 수백 개를 들고 온다 — 200개를 받으면 목록 한 번에 메가바이트 단위가 된다
                .limit(50)
                .execute()
                .value
            failureNotice = nil
        } catch {
            Self.log.error("코스 목록 실패: \(error.localizedDescription, privacy: .public)")
            courses = []
            failureNotice = "코스를 불러오지 못했어요. 연결을 확인해 주세요."
        }
    }

    /// 지역 칩에 붙일 개수. 경로는 빼고 지역 문자열만 받아서 가볍다.
    @MainActor
    func loadRegionCounts(mineOnly: Bool = false, ownerID: UUID? = nil) async {
        struct RegionRow: Decodable { let region: String }
        do {
            var query = supabase.from("courses").select("region")
            if mineOnly, let ownerID { query = query.eq("owner_id", value: ownerID.uuidString) }
            let rows: [RegionRow] = try await query.limit(1_000).execute().value
            var counts = Dictionary(grouping: rows.map(\.region), by: { $0 }).mapValues(\.count)
            counts[KoreaRegion.all] = rows.count
            regionCounts = counts
        } catch {
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
        guard !trimmed.isEmpty else { throw CourseError.tooShort }

        let course = Course(ownerID: ownerID, ownerNickname: ownerNickname,
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            region: region,
                            distanceMeters: CourseGeometry.length(trimmed),
                            path: trimmed)
        try await supabase.from("courses").insert(course).execute()
        courses.insert(course, at: 0)
        return course
    }

    @MainActor
    func delete(_ course: Course) async throws {
        try await supabase.from("courses").delete().eq("id", value: course.id.uuidString).execute()
        courses.removeAll { $0.id == course.id }
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
