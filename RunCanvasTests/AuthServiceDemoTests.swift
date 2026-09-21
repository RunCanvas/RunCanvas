import XCTest
import SwiftData
@testable import RunCanvas

@MainActor
final class AuthServiceDemoTests: XCTestCase {
    private let keys = ["userNickname", "userWeight", "userHeight", "avatarURL"]

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    /// 실기기에서 잡힌 버그: 데모로 들어가도 이전에 로그인했던 계정의 프로필 캐시가 남아,
    /// 아바타 자리에 잠긴 버킷을 가리키는 URL 이 걸려 스피너만 계속 돌았다.
    /// exitDemo 는 비우는데 enterDemo 는 안 비웠다 — 대칭이 깨진 자리.
    func testEnterDemoClearsPreviousProfileCache() throws {
        let defaults = UserDefaults.standard
        defaults.set("이전사용자", forKey: "userNickname")
        defaults.set("https://example.com/locked-bucket/old.jpg", forKey: "avatarURL")
        defaults.set(80.0, forKey: "userWeight")

        let auth = AuthService()
        try XCTSkipUnless(!auth.isSignedIn, "테스트 프로세스에 실제 세션이 있으면 데모 진입이 막힌다")
        auth.enterDemo()

        XCTAssertTrue(auth.isDemo)
        XCTAssertFalse(auth.canSync, "데모 기록이 서버로 올라가면 안 된다")
        keys.forEach { XCTAssertNil(defaults.object(forKey: $0), $0) }
    }

    /// 회귀: 프로필 채우기가 "기록이 이미 있으면 되돌아간다" 뒤에 있던 탓에, 두 번째 진입부터는
    /// enterDemo 가 비운 닉네임이 다시 안 채워져 홈에 기본값 "러너"가 떴다.
    func testSeedFillsProfileEvenWhenRunsAlreadyExist() throws {
        let container = try ModelContainer(for: Run.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let defaults = UserDefaults.standard

        DemoData.seedIfNeeded(context: context)
        let seeded = try context.fetch(FetchDescriptor<Run>()).count
        XCTAssertGreaterThan(seeded, 0)
        XCTAssertEqual(defaults.string(forKey: "userNickname"), "데모")

        Profile.clearLocalCache()          // 두 번째 진입에서 enterDemo 가 하는 일
        DemoData.seedIfNeeded(context: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<Run>()).count, seeded, "기록을 다시 심으면 안 된다")
        XCTAssertEqual(defaults.string(forKey: "userNickname"), "데모")
        XCTAssertEqual(defaults.double(forKey: "userWeight"), 62)
    }
}
