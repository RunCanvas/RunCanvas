import Foundation

/// 세션 안의 한 구간. 런데이식 프로그램은 "3분 달리기 → 2분 걷기"의 반복이라
/// 구간은 종류와 길이(초) 두 가지면 충분하다.
struct TrainingStep: Codable, Equatable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case warmup
        case run
        case walk
        case cooldown

        var id: String { rawValue }
        /// 화면·음성에서 쓰는 이름
        var title: String {
            switch self {
            case .warmup: "준비 걷기"
            case .run: "달리기"
            case .walk: "걷기"
            case .cooldown: "마무리 걷기"
            }
        }
        var isRunning: Bool { self == .run }

        /// 왜: 예전 빌드(develop)는 화면 문구("달리기")를 그대로 저장 키로 썼다. 이 디코더가 없으면
        /// 그 기기의 사용자 프로그램이 통째로 디코드 실패 → 목록에서 사라지고, TrainingStore.save 가
        /// "손상된 저장소"로 보고 조용히 반환해 **새 프로그램도 영영 저장되지 않는다**.
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            switch try container.decode(String.self) {
            case "warmup", "준비 걷기": self = .warmup
            case "run", "달리기": self = .run
            case "walk", "걷기": self = .walk
            case "cooldown", "마무리 걷기": self = .cooldown
            case let value:
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "알 수 없는 트레이닝 구간 종류: \(value)"
                )
            }
        }
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
        let programNumber = 1
        let weeks: [(run: Int, walk: Int, repeats: Int)] = [
            (60, 90, 8), (90, 120, 6), (180, 180, 4), (300, 180, 3),
            (480, 180, 2), (600, 120, 2), (1_200, 0, 1), (1_800, 0, 1)
        ]
        var sessions: [TrainingSession] = []
        for (index, week) in weeks.enumerated() {
            for day in 1...3 {
                let sessionNumber = index * 3 + day
                var steps = [builtInStep(.warmup, seconds: 300, program: programNumber,
                                         session: sessionNumber, index: 1)]
                for repeatIndex in 0..<week.repeats {
                    steps.append(builtInStep(.run, seconds: week.run, program: programNumber,
                                             session: sessionNumber, index: steps.count + 1))
                    // 마지막 반복 뒤 걷기는 마무리 걷기와 겹치므로 넣지 않는다
                    if week.walk > 0, repeatIndex < week.repeats - 1 {
                        steps.append(builtInStep(.walk, seconds: week.walk, program: programNumber,
                                                 session: sessionNumber, index: steps.count + 1))
                    }
                }
                steps.append(builtInStep(.cooldown, seconds: 300, program: programNumber,
                                         session: sessionNumber, index: steps.count + 1))
                sessions.append(TrainingSession(
                    id: builtInID(entity: 2, program: programNumber, session: sessionNumber),
                    title: "\(index + 1)주차 \(day)일",
                    steps: steps
                ))
            }
        }
        return TrainingProgram(
            id: builtInID(entity: 1, program: programNumber),
            name: "8주 5K 만들기",
            summary: "걷기와 달리기를 섞어 8주 동안 5km를 쉬지 않고 달릴 몸을 만듭니다. 주 3회.",
            sessions: sessions,
            isBuiltIn: true
        )
    }()

    /// 이미 뛰는 사람이 30분 연속 달리기를 만드는 4주
    static let thirtyMinutes: TrainingProgram = {
        let programNumber = 2
        let runSeconds = [900, 1_200, 1_500, 1_800]
        let sessions = runSeconds.enumerated().flatMap { index, seconds in
            (1...3).map { day in
                let sessionNumber = index * 3 + day
                return TrainingSession(id: builtInID(entity: 2, program: programNumber, session: sessionNumber),
                                       title: "\(index + 1)주차 \(day)일", steps: [
                    builtInStep(.warmup, seconds: 300, program: programNumber, session: sessionNumber, index: 1),
                    builtInStep(.run, seconds: seconds, program: programNumber, session: sessionNumber, index: 2),
                    builtInStep(.cooldown, seconds: 300, program: programNumber, session: sessionNumber, index: 3)
                ])
            }
        }
        return TrainingProgram(
            id: builtInID(entity: 1, program: programNumber),
            name: "30분 달리기 도전",
            summary: "15분에서 시작해 4주 만에 30분 연속 달리기까지. 주 3회.",
            sessions: sessions,
            isBuiltIn: true
        )
    }()

    /// 속도용 인터벌 한 세션짜리 — 언제든 꺼내 쓰는 단품
    static let intervals: TrainingProgram = {
        let programNumber = 3
        let sessionNumber = 1
        let kindsAndSeconds = [(TrainingStep.Kind.warmup, 300)]
            + (0..<8).flatMap { index in
                [(TrainingStep.Kind.run, 60)]
                    + (index < 7 ? [(TrainingStep.Kind.walk, 120)] : [])
            }
            + [(TrainingStep.Kind.cooldown, 300)]
        let steps = kindsAndSeconds.enumerated().map { index, value in
            builtInStep(value.0, seconds: value.1, program: programNumber,
                        session: sessionNumber, index: index + 1)
        }
        return TrainingProgram(
            id: builtInID(entity: 1, program: programNumber),
            name: "1분 인터벌 8세트",
            summary: "빠르게 1분, 걸으며 2분 회복을 8번. 페이스를 끌어올릴 때.",
            sessions: [TrainingSession(
                id: builtInID(entity: 2, program: programNumber, session: sessionNumber),
                title: "인터벌 1회차",
                steps: steps
            )],
            isBuiltIn: true
        )
    }()

    /// 코드로 다시 만들어도 같은 UUID가 나오게 해 완료 기록이 앱 재실행을 건너 유지된다.
    private static func builtInID(entity: Int, program: Int, session: Int = 0, step: Int = 0) -> UUID {
        UUID(uuidString: String(format: "52554E43-%04d-%04d-%04d-%012d", entity, program, session, step))!
    }

    private static func builtInStep(_ kind: TrainingStep.Kind, seconds: Int,
                                    program: Int, session: Int, index: Int) -> TrainingStep {
        TrainingStep(id: builtInID(entity: 3, program: program, session: session, step: index),
                     kind: kind, seconds: seconds)
    }
}
