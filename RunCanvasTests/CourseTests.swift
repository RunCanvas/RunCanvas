import XCTest
@testable import RunCanvas

final class CourseTests: XCTestCase {
    /// 서울시청 근처에서 동쪽으로 대략 10m 간격의 직선 경로
    private func straightPath(points: Int, spacing: Double = 10) -> [CoursePoint] {
        // 위도 37.5°에서 경도 1도 ≈ 88.4km → 10m ≈ 0.000113°
        let step = spacing / 88_400
        return (0..<points).map { CoursePoint(lat: 37.5665, lon: 126.9780 + Double($0) * step) }
    }

    func testDistanceAndLength() {
        let path = straightPath(points: 11)          // 10칸 × 10m
        XCTAssertEqual(CourseGeometry.distance(path[0], path[1]), 10, accuracy: 0.5)
        XCTAssertEqual(CourseGeometry.length(path), 100, accuracy: 5)
        XCTAssertEqual(CourseGeometry.length([]), 0)
        XCTAssertEqual(CourseGeometry.length([path[0]]), 0)
    }

    /// 집·직장이 드러나지 않게 앞뒤를 자른다
    func testTrimRemovesBothEnds() {
        let path = straightPath(points: 101)          // 약 1000m
        let trimmed = CourseGeometry.trimmed(path)    // 앞뒤 150m
        XCTAssertLessThan(CourseGeometry.length(trimmed), CourseGeometry.length(path))
        XCTAssertEqual(CourseGeometry.length(trimmed), 700, accuracy: 60)
        XCTAssertNotEqual(trimmed.first, path.first, "출발점이 그대로 남으면 자른 의미가 없다")
        XCTAssertNotEqual(trimmed.last, path.last)
    }

    func testTooShortRouteIsRejected() {
        XCTAssertTrue(CourseGeometry.trimmed(straightPath(points: 30)).isEmpty, "300m 기록은 자르고 나면 코스가 아니다")
        XCTAssertTrue(CourseGeometry.trimmed([]).isEmpty)
        XCTAssertTrue(CourseGeometry.trimmed(straightPath(points: 2)).isEmpty)
    }

    /// 1Hz 기록은 제자리 점이 많다 — 5m 미만 간격은 버린다
    func testPathFromRouteDropsCrowdedPoints() {
        let now = Date()
        let route = (0..<10).map { index in
            RoutePoint(latitude: 37.5665 + Double(index) * 0.00001,   // 약 1.1m 간격
                       longitude: 126.9780, timestamp: now.addingTimeInterval(Double(index)))
        }
        let path = CourseGeometry.path(from: route)
        XCTAssertLessThan(path.count, route.count)
        XCTAssertGreaterThan(path.count, 0)
    }

    /// 코스 등록 때 지역을 손으로 고르면 잘못 고른 코스가 섞인다 — 위치에서 추측한 값을 쓴다
    func testAdministrativeAreaBecomesShortRegion() {
        XCTAssertEqual(KoreaRegion.short(administrativeArea: "서울특별시"), "서울")
        XCTAssertEqual(KoreaRegion.short(administrativeArea: "경기도"), "경기")
        XCTAssertEqual(KoreaRegion.short(administrativeArea: "충청북도"), "충북")
        XCTAssertEqual(KoreaRegion.short(administrativeArea: "전북특별자치도"), "전북")
        XCTAssertEqual(KoreaRegion.short(administrativeArea: "강원특별자치도"), "강원")
        XCTAssertEqual(KoreaRegion.short(administrativeArea: "제주특별자치도"), "제주")
        XCTAssertEqual(KoreaRegion.short(administrativeArea: "경상남도"), "경남")
        XCTAssertNil(KoreaRegion.short(administrativeArea: "Tokyo"))
        // 추측한 값은 반드시 칩 목록에 있는 이름이어야 한다 — 아니면 필터에서 사라진다
        for area in ["서울특별시", "경기도", "충청남도", "전라남도", "경상북도"] {
            XCTAssertTrue(KoreaRegion.order.contains(KoreaRegion.short(administrativeArea: area) ?? ""), area)
        }
    }

    func testDecodesServerRow() throws {
        let json = """
        [{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301",
          "owner_id":"3F2504E0-4F89-11D3-9A0C-0305E82C3302",
          "owner_nickname":"동하","name":"한강 5K","region":"서울","distance_m":5012.5,
          "path":[{"lat":37.5,"lon":127.0},{"lat":37.501,"lon":127.001}]}]
        """
        let courses = try JSONDecoder().decode([Course].self, from: Data(json.utf8))
        let course = try XCTUnwrap(courses.first)
        XCTAssertEqual(course.name, "한강 5K")
        XCTAssertEqual(course.ownerNickname, "동하")
        XCTAssertEqual(course.distanceKm, 5.0125, accuracy: 0.0001)
        XCTAssertEqual(course.path.count, 2)
        XCTAssertEqual(course.coordinates.first?.latitude, 37.5)
    }

    /// 올릴 때 쓰는 인코딩이 서버 컬럼 이름과 같아야 한다
    func testEncodesToServerColumns() throws {
        let course = Course(ownerID: UUID(), ownerNickname: "동하", name: "코스", region: "서울",
                            distanceMeters: 1000, path: [CoursePoint(lat: 1, lon: 2)])
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(course)) as? [String: Any]
        XCTAssertEqual(Set(try XCTUnwrap(object).keys),
                       ["id", "owner_id", "owner_nickname", "name", "region", "distance_m", "path"])
    }
}
