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
        guard let data = defaults.data(forKey: key(programsKey, ownerID)),
              let programs = try? JSONDecoder().decode([TrainingProgram].self, from: data) else { return [] }
        return programs
    }

    static func save(_ program: TrainingProgram, ownerID: UUID?, defaults: UserDefaults = .standard) {
        var programs = customPrograms(ownerID: ownerID, defaults: defaults)
        if let index = programs.firstIndex(where: { $0.id == program.id }) {
            programs[index] = program
        } else {
            programs.append(program)
        }
        write(programs, ownerID: ownerID, defaults: defaults)
    }

    static func delete(_ program: TrainingProgram, ownerID: UUID?, defaults: UserDefaults = .standard) {
        write(customPrograms(ownerID: ownerID, defaults: defaults).filter { $0.id != program.id },
              ownerID: ownerID, defaults: defaults)
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

    /// 프로그램에서 몇 개나 했는지 (내장 프로그램은 앱을 지우면 세션 id가 새로 생기므로 진행도 초기화된다 —
    /// ponytail: 서버에 붙일 만큼 중요해지면 그때 `training_progress` 테이블로 옮긴다)
    static func completedCount(in program: TrainingProgram, ownerID: UUID?,
                               defaults: UserDefaults = .standard) -> Int {
        let done = completedSessionIDs(ownerID: ownerID, defaults: defaults)
        return program.sessions.count { done.contains($0.id) }
    }
}
