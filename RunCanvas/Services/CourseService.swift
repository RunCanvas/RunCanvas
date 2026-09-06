import Foundation
import Observation
import Supabase
import OSLog

/// 공유 코스 목록·등록·삭제. 서버(`courses`)가 원본이고 앱은 캐시하지 않는다 —
/// 남이 올린 코스라 언제든 지워질 수 있고, 목록은 들어올 때마다 새로 받으면 그만이다.
@Observable
final class CourseService {
    private static let log = Logger(subsystem: "name.dongharyu.RunCanvas", category: "course")

    private(set) var courses: [Course] = []
    private(set) var isLoading = false
    /// 서버를 못 읽었을 때 화면에 보여줄 한 줄
    private(set) var failureNotice: String?

    @MainActor
    func load(region: String = KoreaRegion.all) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let query = supabase.from("courses").select()
            let filtered = region == KoreaRegion.all ? query : query.eq("region", value: region)
            courses = try await filtered
                .order("created_at", ascending: false)
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
