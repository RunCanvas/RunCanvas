import Foundation
import OSLog
import SwiftData

/// 건강 앱에서 읽어 온 워크아웃 하나. HealthKit 타입을 그대로 들고 다니면 테스트가 실기기를 요구한다.
struct ImportedWorkout: Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let distanceMeters: Double
    let calories: Double
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let route: [RoutePoint]
}

/// 가져올 워크아웃을 어디서 읽는지. HealthService 가 실제 구현이고, 테스트는 가짜를 끼운다 —
/// 이 이음매가 없으면 "기록이 나타나는가 / 두 개가 되는가"를 실기기 없이 확인할 방법이 없다.
protocol WorkoutImporting {
    func requestAuthorization() async throws
    /// `needsRoute` 가 true 인 워크아웃만 경로까지 읽는다. 경로 조회는 한 건당 HealthKit 쿼리 2개라
    /// 90일치를 통째로 읽으면 앱을 열 때마다 수백 번 돈다 — 대부분은 이미 앱에 있어 버려지는데도.
    func importableWorkouts(since: Date,
                            needsRoute: @escaping (ImportedWorkout) -> Bool) async throws -> [ImportedWorkout]
}

extension HealthService: WorkoutImporting {}

/// 이미 앱에 있는 기록을 알아보기 위한 최소 정보. `Run` 을 통째로 넘기면 테스트가 SwiftData 를 끌고 온다.
struct ExistingRun: Equatable {
    let startedAt: Date
    let endedAt: Date
    let healthWorkoutID: UUID?

    init(startedAt: Date, endedAt: Date, healthWorkoutID: UUID? = nil) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.healthWorkoutID = healthWorkoutID
    }
}

/// 건강 앱 워크아웃 → 앱 기록. 순수 함수라 HealthKit 없이 테스트한다.
///
/// 왜 필요한가: 워치로 뛸 때 폰 앱이 떠 있지 않으면 실시간 스냅샷이 전부 사라져 러닝이 앱에 안 남았다.
/// 건강 앱에는 워치가 저장해 두므로, 앱이 열릴 때 거기서 빠진 기록을 채운다.
enum HealthImport {
    /// 같은 러닝으로 볼 시작 시각 차이. 폰과 워치가 같은 러닝을 저장해도 몇 초는 어긋난다.
    static let sameRunTolerance: TimeInterval = 120

    /// 너무 짧은 워크아웃은 가져오지 않는다 — 잘못 눌러 생긴 조각까지 기록으로 만들면 통계가 흐려진다.
    static let minimumSeconds: TimeInterval = 60
    static let minimumMeters: Double = 100

    static func newWorkouts(from workouts: [ImportedWorkout], existing: [ExistingRun]) -> [ImportedWorkout] {
        let knownIDs = Set(existing.compactMap(\.healthWorkoutID))
        return workouts.filter { workout in
            guard workout.endedAt.timeIntervalSince(workout.startedAt) >= minimumSeconds,
                  workout.distanceMeters >= minimumMeters else { return false }
            guard !knownIDs.contains(workout.id) else { return false }
            // 폰이 직접 기록한 러닝은 우리가 건강 앱에도 저장해 둔다 — 그걸 그대로 가져오면 같은 러닝이 두 개가 된다.
            // id 를 모르는 예전 기록까지 걸러야 하므로 시간이 겹치는지로 판단한다.
            return !existing.contains { overlaps($0, workout) }
        }
    }

    private static func overlaps(_ run: ExistingRun, _ workout: ImportedWorkout) -> Bool {
        // 시작이 비슷하거나, 두 구간이 실제로 겹치면 같은 러닝으로 본다
        abs(run.startedAt.timeIntervalSince(workout.startedAt)) <= sameRunTolerance
            || (run.startedAt < workout.endedAt && workout.startedAt < run.endedAt)
    }

    /// 가져온 워크아웃을 저장할 기록으로. 움직인 시간은 건강 앱이 따로 안 주므로 전체 구간으로 둔다.
    static func makeRun(from workout: ImportedWorkout, ownerID: UUID) -> Run {
        Run(
            ownerID: ownerID,
            startedAt: workout.startedAt,
            endedAt: workout.endedAt,
            distanceMeters: workout.distanceMeters,
            movingSeconds: Int(workout.endedAt.timeIntervalSince(workout.startedAt).rounded()),
            calories: workout.calories,
            averageHeartRate: workout.averageHeartRate,
            maxHeartRate: workout.maxHeartRate,
            route: workout.route,
            healthWorkoutID: workout.id
        )
    }
}

// MARK: - 실제 가져오기 (건강 앱 ↔ SwiftData)

extension HealthImport {
    private static let log = Logger(subsystem: "name.dongharyu.RunCanvas", category: "healthImport")
    /// 앱을 열 때마다 훑는 구간. 워치로만 뛴 러닝은 폰이 며칠 뒤에야 열릴 수 있다.
    private static let lookbackDays = 90

    /// 워치가 보내온 요약 하나를 기록으로. 이미 있는 러닝이면 아무것도 안 한다.
    /// 경로는 워치가 건강 앱에만 붙여 두므로 여기선 비어 있고, 다음 가져오기가 채운다.
    @MainActor
    @discardableResult
    static func saveIfMissing(_ workout: ImportedWorkout, ownerID: UUID, context: ModelContext) -> Bool {
        guard let runs = try? context.fetch(
            FetchDescriptor<Run>(predicate: #Predicate { $0.ownerID == ownerID })
        ) else { return false }
        let existing = runs.map { ExistingRun(startedAt: $0.startedAt, endedAt: $0.endedAt,
                                              healthWorkoutID: $0.healthWorkoutID) }
        guard !newWorkouts(from: [workout], existing: existing).isEmpty else { return false }
        context.insert(makeRun(from: workout, ownerID: ownerID))
        guard (try? context.save()) != nil else { return false }
        log.info("워치가 보낸 러닝 1건 저장")
        return true
    }

    /// 건강 앱에 있는데 앱에 없는 러닝을 기록으로 만든다. 실패는 조용히 넘기고 다음 기회에 다시 시도한다.
    @MainActor
    @discardableResult
    static func importMissingRuns(context: ModelContext, ownerID: UUID, health: WorkoutImporting) async -> Int {
        // 읽기 권한이 없으면 조회가 빈손으로 돌아온다. 새로 추가된 읽기 타입은 여기서 한 번 물어본다.
        try? await health.requestAuthorization()

        // 왜 로컬 조회가 먼저: 무엇이 이미 있는지 알아야 '경로까지 읽을 워크아웃'을 고를 수 있다.
        // 왜: 조회가 실패했는데 빈 목록으로 진행하면 이미 있는 러닝을 전부 다시 만든다
        guard let runs = try? context.fetch(
            FetchDescriptor<Run>(predicate: #Predicate { $0.ownerID == ownerID })
        ) else {
            log.error("로컬 기록 조회 실패 — 가져오기 건너뜀")
            return 0
        }
        let existing = runs.map { ExistingRun(startedAt: $0.startedAt, endedAt: $0.endedAt,
                                              healthWorkoutID: $0.healthWorkoutID) }
        // 경로가 필요한 건 둘뿐이다: 새로 만들 기록, 그리고 지도가 비어 있어 채워야 할 기록
        let needsRouteFill = Set(runs.filter { $0.route.isEmpty }.compactMap(\.healthWorkoutID))

        let since = Calendar.appGregorian.date(byAdding: .day, value: -lookbackDays, to: .now) ?? .distantPast
        let workouts: [ImportedWorkout]
        do {
            workouts = try await health.importableWorkouts(since: since) { candidate in
                needsRouteFill.contains(candidate.id)
                    || !newWorkouts(from: [candidate], existing: existing).isEmpty
            }
        } catch {
            log.error("건강 앱 조회 실패: \(error.localizedDescription, privacy: .public)")
            return 0
        }
        guard !workouts.isEmpty else { return 0 }
        // 워치 요약으로 먼저 들어온 기록은 경로가 비어 있다 — 건강 앱에서 읽은 경로로 채운다
        var filledRoutes = 0
        let byWorkoutID = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for run in runs where run.route.isEmpty {
            guard let id = run.healthWorkoutID, let workout = byWorkoutID[id], !workout.route.isEmpty else { continue }
            run.route = workout.route
            filledRoutes += 1
        }

        let missing = newWorkouts(from: workouts, existing: existing)
        guard !missing.isEmpty || filledRoutes > 0 else { return 0 }

        missing.forEach { context.insert(makeRun(from: $0, ownerID: ownerID)) }
        do {
            try context.save()
        } catch {
            log.error("가져온 기록 저장 실패: \(error.localizedDescription, privacy: .public)")
            return 0
        }
        log.info("건강 앱에서 러닝 \(missing.count, privacy: .public)건 가져오고 경로 \(filledRoutes, privacy: .public)건 채움")
        return missing.count
    }
}
