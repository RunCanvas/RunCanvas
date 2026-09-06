import Foundation

/// 세션 안의 한 구간. 런데이식 프로그램은 "3분 달리기 → 2분 걷기"의 반복이라
/// 구간은 종류와 길이(초) 두 가지면 충분하다.
struct TrainingStep: Codable, Equatable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case warmup = "준비 걷기"
        case run = "달리기"
        case walk = "걷기"
        case cooldown = "마무리 걷기"

        var id: String { rawValue }
        /// 화면·음성에서 쓰는 이름
        var title: String { rawValue }
        var isRunning: Bool { self == .run }
    }

    var id = UUID()
    var kind: Kind
    var seconds: Int

    var minutesText: String {
        seconds % 60 == 0 ? "\(seconds / 60)분" : "\(seconds / 60)분 \(seconds % 60)초"
    }
}

/// 한 번에 소화하는 훈련 하나
struct TrainingSession: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var steps: [TrainingStep]

    var totalSeconds: Int { steps.reduce(0) { $0 + $1.seconds } }
    var runningSeconds: Int { steps.filter(\.kind.isRunning).reduce(0) { $0 + $1.seconds } }
}

/// 세션을 순서대로 묶은 프로그램. 내장 프로그램과 사용자가 만든 프로그램이 같은 모양이다.
struct TrainingProgram: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var summary: String
    var sessions: [TrainingSession]
    /// 내장 프로그램은 고칠 수 없다(고치고 싶으면 복제해서 쓴다)
    var isBuiltIn = false

    var totalSeconds: Int { sessions.reduce(0) { $0 + $1.totalSeconds } }
}

// MARK: - 내장 프로그램

extension TrainingProgram {
    /// 앱에 담아 둔 프로그램. 서버 없이 바로 시작할 수 있어야 해서 코드로 만든다.
    static let builtIn: [TrainingProgram] = [couchTo5K, thirtyMinutes, intervals]

    /// 런데이식 8주 5K — 주 3회, 걷기·달리기 반복 길이를 주마다 늘린다.
    /// 표 한 줄이 한 주(달리기 초, 걷기 초, 반복 횟수)라 주차 조정이 표에서 끝난다.
    static let couchTo5K: TrainingProgram = {
        let weeks: [(run: Int, walk: Int, repeats: Int)] = [
            (60, 90, 8), (90, 120, 6), (180, 180, 4), (300, 180, 3),
            (480, 180, 2), (600, 120, 2), (1_200, 0, 1), (1_800, 0, 1)
        ]
        var sessions: [TrainingSession] = []
        for (index, week) in weeks.enumerated() {
            for day in 1...3 {
                var steps = [TrainingStep(kind: .warmup, seconds: 300)]
                for repeatIndex in 0..<week.repeats {
                    steps.append(TrainingStep(kind: .run, seconds: week.run))
                    // 마지막 반복 뒤 걷기는 마무리 걷기와 겹치므로 넣지 않는다
                    if week.walk > 0, repeatIndex < week.repeats - 1 {
                        steps.append(TrainingStep(kind: .walk, seconds: week.walk))
                    }
                }
                steps.append(TrainingStep(kind: .cooldown, seconds: 300))
                sessions.append(TrainingSession(title: "\(index + 1)주차 \(day)일", steps: steps))
            }
        }
        return TrainingProgram(
            name: "8주 5K 만들기",
            summary: "걷기와 달리기를 섞어 8주 동안 5km를 쉬지 않고 달릴 몸을 만듭니다. 주 3회.",
            sessions: sessions,
            isBuiltIn: true
        )
    }()

    /// 이미 뛰는 사람이 30분 연속 달리기를 만드는 4주
    static let thirtyMinutes: TrainingProgram = {
        let runSeconds = [900, 1_200, 1_500, 1_800]
        let sessions = runSeconds.enumerated().flatMap { index, seconds in
            (1...3).map { day in
                TrainingSession(title: "\(index + 1)주차 \(day)일", steps: [
                    TrainingStep(kind: .warmup, seconds: 300),
                    TrainingStep(kind: .run, seconds: seconds),
                    TrainingStep(kind: .cooldown, seconds: 300)
                ])
            }
        }
        return TrainingProgram(
            name: "30분 달리기 도전",
            summary: "15분에서 시작해 4주 만에 30분 연속 달리기까지. 주 3회.",
            sessions: sessions,
            isBuiltIn: true
        )
    }()

    /// 속도용 인터벌 한 세션짜리 — 언제든 꺼내 쓰는 단품
    static let intervals = TrainingProgram(
        name: "1분 인터벌 8세트",
        summary: "빠르게 1분, 걸으며 2분 회복을 8번. 페이스를 끌어올릴 때.",
        sessions: [
            TrainingSession(title: "인터벌 1회차", steps:
                [TrainingStep(kind: .warmup, seconds: 300)]
                + (0..<8).flatMap { index in
                    [TrainingStep(kind: .run, seconds: 60)]
                    + (index < 7 ? [TrainingStep(kind: .walk, seconds: 120)] : [])
                }
                + [TrainingStep(kind: .cooldown, seconds: 300)])
        ],
        isBuiltIn: true
    )
}
