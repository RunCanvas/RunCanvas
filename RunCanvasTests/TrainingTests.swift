import XCTest
@testable import RunCanvas

final class TrainingTests: XCTestCase {
    private let session = TrainingSession(title: "테스트", steps: [
        TrainingStep(kind: .warmup, seconds: 300),
        TrainingStep(kind: .run, seconds: 60),
        TrainingStep(kind: .walk, seconds: 90),
        TrainingStep(kind: .cooldown, seconds: 300)
    ])

    // MARK: 구간 계산

    func testStepAtEachPointOfTheSession() throws {
        let start = try XCTUnwrap(TrainingEngine.progress(elapsed: 0, in: session))
        XCTAssertEqual(start.step.kind, .warmup)
        XCTAssertEqual(start.remainingSeconds, 300)
        XCTAssertEqual(start.next?.kind, .run)

        // 경계: 300초는 준비 걷기가 끝나고 달리기가 시작되는 순간
        let boundary = try XCTUnwrap(TrainingEngine.progress(elapsed: 300, in: session))
        XCTAssertEqual(boundary.step.kind, .run)
        XCTAssertEqual(boundary.remainingSeconds, 60)

        let middle = try XCTUnwrap(TrainingEngine.progress(elapsed: 359, in: session))
        XCTAssertEqual(middle.step.kind, .run)
        XCTAssertEqual(middle.remainingSeconds, 1)

        let last = try XCTUnwrap(TrainingEngine.progress(elapsed: 749, in: session))
        XCTAssertEqual(last.step.kind, .cooldown)
        XCTAssertNil(last.next)
        XCTAssertEqual(last.fraction, 749.0 / 750.0, accuracy: 0.001)
    }

    func testSessionEndsExactlyAtTotalSeconds() {
        XCTAssertEqual(session.totalSeconds, 750)
        XCTAssertNil(TrainingEngine.progress(elapsed: 750, in: session), "끝난 세션은 nil")
        XCTAssertNil(TrainingEngine.progress(elapsed: 5_000, in: session))
        XCTAssertNil(TrainingEngine.progress(elapsed: -1, in: session))
        XCTAssertNil(TrainingEngine.progress(elapsed: 0, in: TrainingSession(title: "빈 세션", steps: [])))
    }

    func testCueMentionsKindAndLength() throws {
        let progress = try XCTUnwrap(TrainingEngine.progress(elapsed: 300, in: session))
        let cue = TrainingEngine.cue(for: progress)
        XCTAssertTrue(cue.contains("1분"), cue)
        XCTAssertTrue(cue.contains("달리기"), cue)
    }

    // MARK: 내장 프로그램

    func testBuiltInProgramsAreUsable() {
        XCTAssertEqual(TrainingProgram.builtIn.count, 3)
        for program in TrainingProgram.builtIn {
            XCTAssertTrue(program.isBuiltIn)
            XCTAssertFalse(program.sessions.isEmpty, program.name)
            for session in program.sessions {
                XCTAssertFalse(session.steps.isEmpty, "\(program.name) / \(session.title)")
                XCTAssertGreaterThan(session.totalSeconds, 0)
                XCTAssertTrue(session.steps.contains { $0.kind.isRunning }, "달리기 없는 훈련은 없다")
            }
        }
    }

    /// 런데이식 8주 × 주 3회
    func testCouchTo5KShape() {
        let program = TrainingProgram.couchTo5K
        XCTAssertEqual(program.sessions.count, 24)
        XCTAssertEqual(program.sessions.first?.title, "1주차 1일")
        XCTAssertEqual(program.sessions.last?.title, "8주차 3일")
        // 마지막 주는 30분 연속 달리기 한 번
        let final = program.sessions.last!
        XCTAssertEqual(final.runningSeconds, 1_800)
        XCTAssertEqual(final.steps.filter { $0.kind == .walk }.count, 0)
        // 주가 갈수록 달리는 시간이 늘어난다
        XCTAssertLessThan(program.sessions[0].runningSeconds, program.sessions[23].runningSeconds)
    }

    // MARK: 저장

    func testCustomProgramsRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "training-tests-\(UUID().uuidString)"))
        let owner = UUID()
        var program = TrainingProgram(name: "내 프로그램", summary: "설명",
                                      sessions: [TrainingSession(title: "1일차",
                                                                 steps: [TrainingStep(kind: .run, seconds: 600)])])

        TrainingStore.save(program, ownerID: owner, defaults: defaults)
        XCTAssertEqual(TrainingStore.customPrograms(ownerID: owner, defaults: defaults).first?.name, "내 프로그램")
        // 다른 계정에는 안 보인다
        XCTAssertTrue(TrainingStore.customPrograms(ownerID: UUID(), defaults: defaults).isEmpty)

        program.name = "이름 바꿈"
        TrainingStore.save(program, ownerID: owner, defaults: defaults)
        let saved = TrainingStore.customPrograms(ownerID: owner, defaults: defaults)
        XCTAssertEqual(saved.count, 1, "같은 id 는 덮어써야 한다")
        XCTAssertEqual(saved.first?.name, "이름 바꿈")

        TrainingStore.delete(program, ownerID: owner, defaults: defaults)
        XCTAssertTrue(TrainingStore.customPrograms(ownerID: owner, defaults: defaults).isEmpty)
    }

    func testCompletedSessionsAreCountedPerProgram() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "training-progress-\(UUID().uuidString)"))
        let owner = UUID()
        let program = TrainingProgram.couchTo5K

        XCTAssertEqual(TrainingStore.completedCount(in: program, ownerID: owner, defaults: defaults), 0)
        TrainingStore.markCompleted(program.sessions[0], ownerID: owner, defaults: defaults)
        TrainingStore.markCompleted(program.sessions[1], ownerID: owner, defaults: defaults)
        TrainingStore.markCompleted(program.sessions[1], ownerID: owner, defaults: defaults)   // 두 번 눌러도 하나
        XCTAssertEqual(TrainingStore.completedCount(in: program, ownerID: owner, defaults: defaults), 2)
        XCTAssertEqual(TrainingStore.completedCount(in: .intervals, ownerID: owner, defaults: defaults), 0)
    }

    func testBuiltInIDsAndProgressSurviveReconstruction() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "training-stable-progress-\(UUID().uuidString)"))
        let owner = UUID()
        let original = TrainingProgram.couchTo5K
        let rebuilt = try JSONDecoder().decode(
            TrainingProgram.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(original.id.uuidString, "52554E43-0001-0001-0000-000000000000")
        XCTAssertEqual(original.sessions.first?.id.uuidString, "52554E43-0002-0001-0001-000000000000")
        XCTAssertEqual(rebuilt.sessions.map(\.id), original.sessions.map(\.id))

        TrainingStore.markCompleted(original.sessions[0], ownerID: owner, defaults: defaults)
        XCTAssertEqual(TrainingStore.completedCount(in: rebuilt, ownerID: owner, defaults: defaults), 1)
    }

    /// 저장 키는 화면 문구와 분리돼 있어야 한다 — 문구를 다듬어도 저장된 프로그램이 안 깨지게
    func testStepKindStoresStableKeyNotDisplayText() throws {
        let encoded = String(data: try JSONEncoder().encode(TrainingStep.Kind.run), encoding: .utf8)
        XCTAssertEqual(encoded, "\"run\"")
        XCTAssertEqual(TrainingStep.Kind.run.title, "달리기")
    }

    func testSaveDoesNotOverwriteUndecodablePrograms() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "training-corrupt-\(UUID().uuidString)"))
        let owner = UUID()
        let key = "trainingPrograms.\(owner.uuidString)"
        let corrupt = Data("not-json".utf8)
        defaults.set(corrupt, forKey: key)

        TrainingStore.save(
            TrainingProgram(name: "새 프로그램", summary: "", sessions: [session]),
            ownerID: owner,
            defaults: defaults
        )

        XCTAssertEqual(defaults.data(forKey: key), corrupt)
    }
}
