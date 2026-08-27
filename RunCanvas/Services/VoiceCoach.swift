import AVFoundation

/// 러닝 중 음성 안내 — iOS 내장 TTS. 안내 중엔 음악이 잠깐 작아졌다 돌아온다(덕킹).
/// 설정은 UserDefaults(`Keys`)에 있고 설정 화면(VoiceSettingsView)이 같은 키를 쓴다.
final class VoiceCoach: NSObject, AVSpeechSynthesizerDelegate {
    enum Keys {
        static let enabled = "voiceGuideEnabled"          // Bool, 기본 true
        static let interval = "voiceGuideIntervalMeters"  // Double, 기본 1000
        static let language = "voiceGuideLanguage"        // "ko" | "en"
        static let voiceID = "voiceGuideVoiceID"          // AVSpeechSynthesisVoice.identifier, 없으면 언어 기본 음성
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
    var language: VoiceCue.Language { VoiceCue.Language(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .ko }

    func speak(_ text: String) {
        if let speaker { speaker(text); return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(id: defaults.string(forKey: Keys.voiceID), language: language)
        synthesizer.speak(utterance)
    }

    /// 안내가 끝나면 오디오 세션을 내려 음악 볼륨을 되돌린다
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: 음성 목록

    /// 선택한 음성이 그 언어 것이면 사용, 아니면 언어 기본 음성
    static func voice(id: String?, language: VoiceCue.Language) -> AVSpeechSynthesisVoice? {
        if let id, !id.isEmpty, let v = AVSpeechSynthesisVoice(identifier: id), v.language.hasPrefix(language.bcp47Prefix) { return v }
        return AVSpeechSynthesisVoice(language: language.defaultBCP47)
    }

    /// 기기에 설치된 그 언어 음성 (프리미엄 → 향상됨 → 기본, 이름순). 향상됨/프리미엄은 iOS 설정에서 내려받으면 여기 나타난다.
    static func voices(for language: VoiceCue.Language) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language.bcp47Prefix) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { a, b in
                a.quality.rawValue != b.quality.rawValue ? a.quality.rawValue > b.quality.rawValue : a.name < b.name
            }
    }

    static func qualityTitle(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: "프리미엄"
        case .enhanced: "향상됨"
        default: "기본"
        }
    }
}

// MARK: - 안내 문장 (순수 함수)

enum VoiceCue {
    enum Language: String, CaseIterable, Identifiable {
        case ko, en
        var id: String { rawValue }
        var title: String { self == .ko ? "한국어" : "English" }
        var bcp47Prefix: String { rawValue }
        var defaultBCP47: String { self == .ko ? "ko-KR" : "en-US" }
    }

    static func start(_ l: Language) -> String { l == .ko ? "러닝 시작" : "Run started" }
    static func pause(_ l: Language) -> String { l == .ko ? "일시정지" : "Paused" }
    static func resume(_ l: Language) -> String { l == .ko ? "다시 시작" : "Resumed" }

    /// 구간 안내: "1킬로미터. 시간 6분 12초. 페이스 6분 12초."
    static func progress(distanceMeters: Double, seconds: Int, language l: Language) -> String {
        let pace = RunMath.paceSecondsPerKm(distanceMeters: distanceMeters, seconds: seconds).map { duration(Int($0.rounded()), l) }
        switch l {
        case .ko: return "\(distance(distanceMeters, l)). 시간 \(duration(seconds, l))." + (pace.map { " 페이스 \($0)." } ?? "")
        case .en: return "\(distance(distanceMeters, l)). Time \(duration(seconds, l))." + (pace.map { " Pace \($0) per kilometer." } ?? "")
        }
    }

    static func finish(distanceMeters: Double, seconds: Int, language l: Language) -> String {
        switch l {
        case .ko: "러닝 종료. 총 \(distance(distanceMeters, l)), \(duration(seconds, l))."
        case .en: "Run complete. \(distance(distanceMeters, l)) in \(duration(seconds, l))."
        }
    }

    static func distance(_ meters: Double, _ l: Language) -> String {
        let km = meters / 1000
        let number = km == km.rounded(.down) ? String(Int(km)) : String(format: "%.1f", km)
        switch l {
        case .ko: return "\(number)킬로미터"
        case .en: return "\(number) kilometer" + (km == 1 ? "" : "s")
        }
    }

    /// "1시간 2분 5초" — 0인 단위는 생략 (0초면 "0초")
    static func duration(_ seconds: Int, _ l: Language) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        var parts: [String] = []
        switch l {
        case .ko:
            if h > 0 { parts.append("\(h)시간") }
            if m > 0 { parts.append("\(m)분") }
            if s > 0 || parts.isEmpty { parts.append("\(s)초") }
        case .en:
            if h > 0 { parts.append("\(h) hour" + (h == 1 ? "" : "s")) }
            if m > 0 { parts.append("\(m) minute" + (m == 1 ? "" : "s")) }
            if s > 0 || parts.isEmpty { parts.append("\(s) second" + (s == 1 ? "" : "s")) }
        }
        return parts.joined(separator: " ")
    }
}
