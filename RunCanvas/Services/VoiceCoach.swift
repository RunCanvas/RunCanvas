import AVFoundation
import OSLog

/// 러닝 중 음성 안내 — iOS 내장 한국어 TTS(기본 음성). 안내 중엔 음악이 잠깐 작아졌다 돌아온다(덕킹).
/// 설정은 UserDefaults(`Keys`)에 있고 설정 화면(VoiceSettingsView)이 같은 키를 쓴다.
final class VoiceCoach: NSObject, AVSpeechSynthesizerDelegate {
    private static let log = Logger(subsystem: "com.daun1997.RunCanvas", category: "voice")

    enum Keys {
        static let enabled = "voiceGuideEnabled"            // Bool, 기본 true
        static let interval = "voiceGuideIntervalMeters"    // Double, 기본 1000
        static let mode = "voiceGuideMode"                  // CueMode.rawValue, 기본 distance
        static let intervalSeconds = "voiceGuideIntervalSeconds"  // Int, 기본 300
    }

    /// 안내를 무엇마다 할지. 거리 기준은 실내에서 영영 안 울리므로, 시간 기준도 둔다 —
    /// 러너가 시간 스플릿을 원하기도 하고, 심사자가 앉은 채로 백그라운드 음성을 확인할 수 있는
    /// 유일한 길이기도 하다(2.5.4 거절 대응, 2026-09-18).
    enum CueMode: String {
        case distance, time
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let defaults: UserDefaults
    /// 테스트용 — 지정하면 TTS 대신 이 클로저로 문장을 보낸다
    var speaker: ((String) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        synthesizer.delegate = self
    }

    var isEnabled: Bool { defaults.object(forKey: Keys.enabled) as? Bool ?? true }
    var intervalMeters: Double { let v = defaults.double(forKey: Keys.interval); return v > 0 ? v : 1000 }
    var mode: CueMode { CueMode(rawValue: defaults.string(forKey: Keys.mode) ?? "") ?? .distance }
    var intervalSeconds: Int { let v = defaults.integer(forKey: Keys.intervalSeconds); return v > 0 ? v : 300 }

    func speak(_ text: String) {
        if let speaker { speaker(text); return }
        let session = AVAudioSession.sharedInstance()
        // 왜 try? 를 쓰지 않는가: 백그라운드에서 세션 활성화가 실패하면 음성이 통째로 안 나가는데,
        // 삼켜 버리면 기기에서 무음인 이유를 영영 알 수 없다(2.5.4 거절 때 실제로 그랬다).
        do {
            try session.setCategory(.playback, mode: .spokenAudio,
                                    options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            Self.log.error("오디오 세션 활성화 실패: \(error.localizedDescription, privacy: .public)")
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")   // ponytail: 기본 음성 하나. 목소리 선택·다른 언어는 2.0
        pending += 1
        synthesizer.speak(utterance)
    }

    /// 안내가 끝나면 오디오 세션을 내려 음악 볼륨을 되돌린다
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        utteranceEnded()
    }

    /// 취소(stopSpeaking)로 끝날 때도 세션을 내려야 음악이 계속 작아진 채 남지 않는다
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        utteranceEnded()
    }

    /// 아직 안 끝난 안내 수. `synthesizer.isSpeaking` 을 쓰지 않는 이유: didFinish 콜백 안에서는
    /// 아직 true 로 나올 때가 있어, 그걸 믿고 되돌아가면 세션을 영영 안 내린다.
    private var pending = 0

    private func utteranceEnded() {
        // 델리게이트 콜백 스레드가 보장되지 않는다 — pending 은 메인에서만 만진다
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            pending = max(0, pending - 1)
            guard pending == 0 else { return }
            scheduleDeactivate()
        }
    }

    /// 왜 곧바로 안 내리는가: 안내가 끝난 순간엔 오디오가 아직 비워지는 중이라
    /// `setActive(false)` 가 IsBusy 로 튕긴다. 그러면 덕킹이 풀리지 않아 음악이 작아진 채로 남는다
    /// (실기기에서 확인 — 에어팟으로 음악을 틀어 두면 바로 드러난다).
    /// 잠깐 뒤에 내리고, 그래도 실패하면 몇 번 더 시도한다.
    private func scheduleDeactivate(after delay: TimeInterval = 0.5, retries: Int = 3) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, pending == 0 else { return }   // 그새 다음 안내가 시작됐으면 그쪽이 책임진다
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                guard retries > 0 else {
                    Self.log.error("오디오 세션 비활성화 실패 — 음악이 작아진 채로 남는다: \(error.localizedDescription, privacy: .public)")
                    return
                }
                scheduleDeactivate(after: 0.5, retries: retries - 1)
            }
        }
    }
}

// MARK: - 안내 문장 (순수 함수)

enum VoiceCue {
    static let start = "러닝 시작"
    static let pause = "일시정지"
    static let resume = "다시 시작"

    /// 구간 안내: "1킬로미터. 시간 6분 12초. 페이스 6분 12초."
    static func progress(distanceMeters: Double, seconds: Int) -> String {
        let pace = RunMath.paceSecondsPerKm(distanceMeters: distanceMeters, seconds: seconds).map { duration(Int($0.rounded())) }
        return "\(distance(distanceMeters)). 시간 \(duration(seconds))." + (pace.map { " 페이스 \($0)." } ?? "")
    }

    static func finish(distanceMeters: Double, seconds: Int) -> String {
        "러닝 종료. 총 \(distance(distanceMeters)), \(duration(seconds))."
    }

    static func distance(_ meters: Double) -> String {
        let km = meters / 1000
        return (km == km.rounded(.down) ? String(Int(km)) : String(format: "%.1f", km)) + "킬로미터"
    }

    /// "1시간 2분 5초" — 0인 단위는 생략 (0초면 "0초")
    static func duration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h)시간") }
        if m > 0 { parts.append("\(m)분") }
        if s > 0 || parts.isEmpty { parts.append("\(s)초") }
        return parts.joined(separator: " ")
    }
}
