import XCTest
@testable import RunCanvas

/// 따라뛰기 계산 — 코스를 얼마나 왔는지, 얼마나 벗어났는지
final class CourseFollowTests: XCTestCase {
    /// 위도 37.5°에서 동쪽으로 10m 간격
    private let step = 10.0 / 88_400
    private lazy var path: [CoursePoint] = (0..<11).map {
        CoursePoint(lat: 37.5665, lon: 126.9780 + Double($0) * step)
    }

    func testNearestIndex() {
        XCTAssertEqual(CourseGeometry.nearestIndex(to: path[0], in: path), 0)
        XCTAssertEqual(CourseGeometry.nearestIndex(to: path[7], in: path), 7)
        XCTAssertNil(CourseGeometry.nearestIndex(to: path[0], in: []))
    }

    func testProgressGrowsAlongTheCourse() {
        XCTAssertEqual(CourseGeometry.progress(at: path[0], in: path), 0, accuracy: 0.01)
        XCTAssertEqual(CourseGeometry.progress(at: path[5], in: path), 0.5, accuracy: 0.05)
        XCTAssertEqual(CourseGeometry.progress(at: path.last!, in: path), 1, accuracy: 0.01)
    }

    /// 되돌아 뛰면 진행도도 줄어야 한다 — 실제로 코스를 덜 지난 상태이므로
    func testProgressFallsWhenRunningBack() {
        let forward = CourseGeometry.progress(at: path[8], in: path)
        let back = CourseGeometry.progress(at: path[3], in: path)
        XCTAssertLessThan(back, forward)
    }

    func testOffCourseDistance() {
        let onCourse = CoursePoint(lat: 37.5665, lon: 126.9780 + step * 4)
        XCTAssertEqual(CourseGeometry.offCourseMeters(onCourse, path: path), 0, accuracy: 1)

        // 북쪽으로 약 111m (위도 0.001°)
        let away = CoursePoint(lat: 37.5675, lon: 126.9780 + step * 4)
        XCTAssertEqual(CourseGeometry.offCourseMeters(away, path: path), 111, accuracy: 10)
    }

    func testEmptyCourseIsSafe() {
        XCTAssertEqual(CourseGeometry.progress(at: path[0], in: []), 0)
        XCTAssertEqual(CourseGeometry.offCourseMeters(path[0], path: []), 0)
    }

    func testRoundTripProgressDoesNotJumpBackAtOverlappingPoints() throws {
        let outbound = (0...80).map {
            CoursePoint(lat: 37.5665, lon: 126.9780 + Double($0) * step)
        }
        let roundTrip = outbound + outbound.dropLast().reversed()

        try assertSequentialProgressReachesEnd(on: roundTrip)
    }

    func testLoopProgressReachesEndWhenFinishOverlapsStart() throws {
        let center = CoursePoint(lat: 37.5665, lon: 126.9780)
        let radius = 0.0005
        let loop = (0...120).map { index in
            let angle = Double(index) / 120 * 2 * Double.pi
            return CoursePoint(
                lat: center.lat + sin(angle) * radius,
                lon: center.lon + cos(angle) * radius
            )
        }

        try assertSequentialProgressReachesEnd(on: loop)
    }

    private func assertSequentialProgressReachesEnd(on course: [CoursePoint],
                                                    file: StaticString = #filePath,
                                                    line: UInt = #line) throws {
        var lastIndex: Int?
        var previousProgress = 0.0
        for point in course {
            let match = try XCTUnwrap(
                CourseGeometry.match(to: point, in: course, near: lastIndex),
                file: file,
                line: line
            )
            lastIndex = match.index
            let progress = CourseGeometry.progress(through: match.index, in: course)
            XCTAssertGreaterThanOrEqual(progress, previousProgress, file: file, line: line)
            previousProgress = progress
        }
        XCTAssertEqual(lastIndex, course.indices.last, file: file, line: line)
        XCTAssertEqual(previousProgress, 1, accuracy: 0.0001, file: file, line: line)
    }
}
