import XCTest
@testable import RunCanvas

@MainActor
final class MarathonServiceTests: XCTestCase {
    func testCachedEventsAppearWhileServerRefreshIsInFlight() async {
        let cached = MarathonEvent(name: "캐시 대회", date: nil)
        let fresh = MarathonEvent(name: "최신 대회", date: nil)
        let fetch = ControlledMarathonFetch(result: [fresh])
        let service = MarathonService(
            fetchEvents: { await fetch.call() },
            readCachedEvents: { [cached] },
            readBundledEvents: { [] },
            storeCachedEvents: { _ in }
        )

        let load = Task { await service.load() }
        await fetch.waitUntilStarted()

        XCTAssertEqual(service.events, [cached])
        XCTAssertTrue(service.isLoading)

        await fetch.finish()
        await load.value
        XCTAssertEqual(service.events, [fresh])
        XCTAssertFalse(service.isLoading)
    }

    func testConcurrentRefreshWaitsForOneSharedRequest() async {
        let fresh = MarathonEvent(name: "최신 대회", date: nil)
        let fetch = ControlledMarathonFetch(result: [fresh])
        let service = MarathonService(
            fetchEvents: { await fetch.call() },
            readCachedEvents: { nil },
            readBundledEvents: { [] },
            storeCachedEvents: { _ in }
        )

        let first = Task { await service.load() }
        await fetch.waitUntilStarted()
        let second = Task { await service.load() }
        // 두 번째 호출이 MainActor에서 진행 중 Task를 발견할 기회를 준다.
        await Task.yield()

        await fetch.finish()
        await first.value
        await second.value

        let callCount = await fetch.callCount
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(service.events, [fresh])
        XCTAssertFalse(service.isLoading)
    }
}

private actor ControlledMarathonFetch {
    let result: [MarathonEvent]
    private(set) var callCount = 0
    private var started = false
    private var isFinished = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []

    init(result: [MarathonEvent]) {
        self.result = result
    }

    func call() async -> [MarathonEvent] {
        callCount += 1
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()

        if !isFinished {
            await withCheckedContinuation { finishWaiters.append($0) }
        }
        return result
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish() {
        isFinished = true
        finishWaiters.forEach { $0.resume() }
        finishWaiters.removeAll()
    }
}
