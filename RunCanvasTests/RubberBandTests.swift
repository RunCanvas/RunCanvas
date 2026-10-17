import XCTest
@testable import RunCanvas

final class RubberBandTests: XCTestCase {

    private let range: ClosedRange<CGFloat> = 0.05...0.95

    func testInsideRangeFollowsOneToOne() {
        XCTAssertEqual(CGFloat(0.5).rubberBanded(into: range), 0.5)
        XCTAssertEqual(CGFloat(0.95).rubberBanded(into: range), 0.95)
    }

    /// 넘어간 만큼보다 덜 따라오고, 아무리 끌어도 dimension(0.2) 밖으로는 못 나간다
    func testOvershootIsResistedAndBounded() {
        let pastUpper = CGFloat(1.15).rubberBanded(into: range)
        XCTAssertGreaterThan(pastUpper, 0.95)
        XCTAssertLessThan(pastUpper, 1.15)
        XCTAssertLessThan(CGFloat(100).rubberBanded(into: range), 0.95 + 0.2)

        let pastLower = CGFloat(-0.15).rubberBanded(into: range)
        XCTAssertLessThan(pastLower, 0.05)
        XCTAssertGreaterThan(pastLower, -0.15)
        XCTAssertGreaterThan(CGFloat(-100).rubberBanded(into: range), 0.05 - 0.2)
    }

    /// 더 끌면 더 나가야 한다 — 어느 지점에서 멈추거나 되돌아오면 손가락과 어긋나 보인다
    func testOvershootIsMonotonic() {
        let samples = stride(from: 0.95, through: 2.0, by: 0.05).map { CGFloat($0).rubberBanded(into: range) }
        XCTAssertEqual(samples, samples.sorted())
    }
}
