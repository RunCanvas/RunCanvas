import SwiftUI
import AVFoundation

/// 음성 안내 설정 — 켜기/간격/언어/음성 선택(탭하면 미리 듣기)
struct VoiceSettingsView: View {
    @AppStorage(VoiceCoach.Keys.enabled) private var isEnabled = true
    @AppStorage(VoiceCoach.Keys.interval) private var intervalMeters = 1000.0
    @AppStorage(VoiceCoach.Keys.language) private var languageRaw = VoiceCue.Language.ko.rawValue
    @AppStorage(VoiceCoach.Keys.voiceID) private var voiceID = ""
    @State private var coach = VoiceCoach()

    private var language: VoiceCue.Language { VoiceCue.Language(rawValue: languageRaw) ?? .ko }
    private var voices: [AVSpeechSynthesisVoice] { VoiceCoach.voices(for: language) }
    private var selectedID: String { VoiceCoach.voice(id: voiceID, language: language)?.identifier ?? "" }

    var body: some View {
        List {
            Section {
                Toggle("음성 안내", isOn: $isEnabled)
            } footer: {
                Text("달리는 동안 거리·시간·페이스를 읽어줘요. 에어팟 등 연결된 이어폰으로 나오고, 음악은 안내 중 잠깐 작아져요.")
            }

            if isEnabled {
                Section("안내 간격") {
                    Picker("간격", selection: $intervalMeters) {
                        Text("500m").tag(500.0)
                        Text("1km").tag(1000.0)
                        Text("2km").tag(2000.0)
                    }
                    .pickerStyle(.segmented)
                }

                Section("언어") {
                    Picker("언어", selection: $languageRaw) {
                        ForEach(VoiceCue.Language.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: languageRaw) { _, _ in voiceID = "" }
                }

                Section {
                    ForEach(voices, id: \.identifier) { voice in
                        Button {
                            voiceID = voice.identifier
                            preview()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(voice.name)
                                    Text(VoiceCoach.qualityTitle(voice))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if voice.identifier == selectedID {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("음성")
                } footer: {
                    Text("탭하면 미리 들을 수 있어요. 더 자연스러운 음성은 iPhone 설정 → 손쉬운 사용 → 음성 콘텐츠 → 음성에서 '향상됨'이나 '프리미엄'을 내려받으면 이 목록에 나타나요.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("음성 안내")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func preview() {
        coach.speak(VoiceCue.progress(distanceMeters: 1000, seconds: 372, language: language))
    }
}

#Preview {
    NavigationStack { VoiceSettingsView() }
}
