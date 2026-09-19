import Foundation

/// 사용자가 만든 프로그램과 "어느 세션까지 했는지"를 계정별로 저장한다.
/// 뱃지(`BadgeStore`)와 같은 방식 — 개수가 적고 기기 안에서만 의미가 있어 UserDefaults로 충분하다.
enum TrainingStore {
    private static let programsKey = "trainingPrograms"
    private static let completedKey = "trainingCompletedSessions"

    private static func key(_ base: String, _ ownerID: UUID?) -> String {
        "\(base).\(ownerID?.uuidString ?? "guest")"
    }

    // MARK: 내가 만든 프로그램

    static func customPrograms(ownerID: UUID?, defaults: UserDefaults = .standard) -> [TrainingProgram] {
        decodedCustomPrograms(ownerID: ownerID, defaults: defaults) ?? []
    }

    static func save(_ program: TrainingProgram, ownerID: UUID?, defaults: UserDefaults = .standard) {
        // 데이터가 있는데 읽지 못한 경우 빈 목록으로 간주하면 다음 저장이 기존 프로그램 전체를 덮어쓴다.
        guard var programs = decodedCustomPrograms(ownerID: ownerID, defaults: defaults) else { return }
        if let index = programs.firstIndex(where: { $0.id == program.id }) {
            programs[index] = program
        } else {
            programs.append(program)
        }
        write(programs, ownerID: ownerID, defaults: defaults)
    }

    static func delete(_ program: TrainingProgram, ownerID: UUID?, defaults: UserDefaults = .standard) {
        guard let programs = decodedCustomPrograms(ownerID: ownerID, defaults: defaults) else { return }
        write(programs.filter { $0.id != program.id }, ownerID: ownerID, defaults: defaults)
    }

    /// 빈 저장소는 빈 배열, 손상된 저장소는 nil로 구분해 파괴적인 덮어쓰기를 막는다.
    private static func decodedCustomPrograms(ownerID: UUID?, defaults: UserDefaults) -> [TrainingProgram]? {
        guard let data = defaults.data(forKey: key(programsKey, ownerID)) else { return [] }
        return try? JSONDecoder().decode([TrainingProgram].self, from: data)
    }

    private static func write(_ programs: [TrainingProgram], ownerID: UUID?, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(programs) else { return }
        defaults.set(data, forKey: key(programsKey, ownerID))
    }

    // MARK: 완료한 세션

    static func completedSessionIDs(ownerID: UUID?, defaults: UserDefaults = .standard) -> Set<UUID> {
        let raw = defaults.stringArray(forKey: key(completedKey, ownerID)) ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    static func markCompleted(_ session: TrainingSession, ownerID: UUID?, defaults: UserDefaults = .standard) {
        var ids = completedSessionIDs(ownerID: ownerID, defaults: defaults)
        ids.insert(session.id)
        defaults.set(ids.map(\.uuidString), forKey: key(completedKey, ownerID))
    }

    /// 프로그램에서 몇 개나 했는지. 내장 세션 id도 고정이라 앱 재실행 뒤 완료 기록과 다시 연결된다.
    static func completedCount(in program: TrainingProgram, ownerID: UUID?,
                               defaults: UserDefaults = .standard) -> Int {
        let done = completedSessionIDs(ownerID: ownerID, defaults: defaults)
        return program.sessions.count { done.contains($0.id) }
    }

    /// 회원 탈퇴 시 그 계정의 캐시만 삭제 (BadgeStore.reset 과 같은 역할).
    /// 없으면 탈퇴한 계정의 사용자 제작 프로그램이 이 기기에 영원히 남는다.
    static func reset(for ownerID: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(programsKey, ownerID))
        defaults.removeObject(forKey: key(completedKey, ownerID))
    }
}
