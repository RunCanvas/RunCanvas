import XCTest
@testable import RunCanvas

final class WatchConnectivityServiceTests: XCTestCase {
    func testStartCommandRejectsMissingStaleAndFarFutureTimestamps() {
        let now = 10_000.0
        XCTAssertFalse(WatchConnectivityService.isFreshStartCommand(timestamp: 0, now: now))
        XCTAssertFalse(WatchConnectivityService.isFreshStartCommand(timestamp: now - 120, now: now))
        XCTAssertFalse(WatchConnectivityService.isFreshStartCommand(timestamp: now + 31, now: now))
    }

    func testStartCommandAcceptsRecentTimestampAndSmallClockSkew() {
        let now = 10_000.0
        XCTAssertTrue(WatchConnectivityService.isFreshStartCommand(timestamp: now - 119, now: now))
        XCTAssertTrue(WatchConnectivityService.isFreshStartCommand(timestamp: now + 30, now: now))
    }
}
