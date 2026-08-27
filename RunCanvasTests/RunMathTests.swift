import XCTest
@testable import RunCanvas

final class RunMathTests: XCTestCase {
    func testPace5kmIn30MinIs6MinPerKm() {
        XCTAssertEqual(RunMath.paceSecondsPerKm(distanceMeters: 5000, seconds: 1800), 360)
    }
    func testPaceIsNilForTinyDistance() {
        XCTAssertNil(RunMath.paceSecondsPerKm(distanceMeters: 3, seconds: 10))
    }
    func testFormatPace() {
        XCTAssertEqual(RunMath.formatPace(330), "05'30\"")
        XCTAssertEqual(RunMath.formatPace(nil), "--'--\"")
    }
    func testFormatDuration() {
        XCTAssertEqual(RunMath.formatDuration(123), "02:03")
        XCTAssertEqual(RunMath.formatDuration(3723), "1:02:03")
    }
    func testCaloriesUsesWeightTimesKm() {
        XCTAssertEqual(RunMath.calories(distanceMeters: 10_000, weightKg: 60), 621.6, accuracy: 0.01)
    }
    func testFormatKm() {
        XCTAssertEqual(RunMath.formatKm(5240), "5.24")
    }
}
