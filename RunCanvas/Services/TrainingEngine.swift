import Foundation

/// 세션이 시작된 뒤 흐른 시간으로 "지금 몇 번째 구간인지"를 계산한다.
/// 순수 함수라 타이머 없이 테스트할 수 있고, 화면은 초마다 이걸 물어보기만 한다.
enum TrainingEngine {
    struct Progress: Equatable {
        let index: Int
        let step: TrainingStep
        /// 이 구간이 끝나기까지 남은 초
        let remainingSeconds: Int
        let next: TrainingStep?
        /// 세션 전체 진행도 0…1
        let fraction: Double
    }

    /// 흐른 시간이 세션 길이를 넘었으면 nil — 끝났다는 뜻.
    static func progress(elapsed: Int, in session: TrainingSession) -> Progress? {
        let total = session.totalSeconds
        guard total > 0, elapsed >= 0, elapsed < total else { return nil }

        var boundary = 0
        for (index, step) in session.steps.enumerated() {
            let next = boundary + step.seconds
            if elapsed < next {
                return Progress(
                    index: index,
                    step: step,
                    remainingSeconds: next - elapsed,
                    next: index + 1 < session.steps.count ? session.steps[index + 1] : nil,
                    fraction: Double(elapsed) / Double(total)
                )
            }
            boundary = next
        }
        return nil
    }

    /// 구간이 바뀌는 순간인지 — 화면이 매초 물어보고, 맞으면 그때만 음성으로 알린다.
    static func startsNewStep(elapsed: Int, in session: TrainingSession) -> Bool {
        guard elapsed > 0 else { return true }
        var boundary = 0
        for step in session.steps {
            boundary += step.seconds
            if boundary == elapsed { return true }
        }
        return false
    }

    /// 구간 전환 안내 문구
    static func cue(for progress: Progress) -> String {
        let step = progress.step
        let length = step.seconds >= 60 ? step.minutesText : "\(step.seconds)초"
        return switch step.kind {
        case .warmup: "준비 걷기 \(length) 시작합니다"
        case .run: "\(length) 달리기 시작"
        case .walk: "\(length) 걸으며 회복하세요"
        case .cooldown: "마무리 걷기 \(length)"
        }
    }

    static let finishCue = "훈련 완료. 수고했어요"
}
