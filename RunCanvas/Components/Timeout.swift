import Foundation

/// op가 seconds 안에 안 끝나면 CancellationError.
/// PhotosPicker의 `loadTransferable`처럼 영영 안 돌아올 수 있는 비동기 작업에 건다.
/// (ProfileEditView 안에 같은 구현이 private으로 하나 더 있다 — 그 파일을 손볼 때 이걸로 합칠 것)
func withTimeoutValue<T: Sendable>(seconds: Double, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await op() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw CancellationError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
