import AVFoundation

/// 러닝 중 음성 안내 — iOS 내장 한국어 TTS(기본 음성). 안내 중엔 음악이 잠깐 작아졌다 돌아온다(덕킹).
/// 설정은 UserDefaults(`Keys`)에 있고 설정 화면(VoiceSettingsView)이 같은 키를 쓴다.
final class VoiceCoach: NSObject, AVSpeechSynthesizerDelegate {
    enum Keys {
        static let enabled = "voiceGuideEnabled"          // Bool, 기본 true
        static let interval = "voiceGuideIntervalMeters"  // Double, 기본 1000
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

    func speak(_ text: String) {
        if let speaker { speaker(text); return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")   // ponytail: 기본 음성 하나. 목소리 선택·다른 언어는 2.0
        synthesizer.speak(utterance)
    }

    /// 안내가 끝나면 오디오 세션을 내려 음악 볼륨을 되돌린다
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
