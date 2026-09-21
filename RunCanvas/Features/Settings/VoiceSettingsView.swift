import SwiftUI

/// 음성 안내 설정 — 켜기/끄기, 안내 간격. 음성은 iOS 기본 한국어 음성 하나 (목소리 선택은 2.0)
struct VoiceSettingsView: View {
    @AppStorage(VoiceCoach.Keys.enabled) private var isEnabled = true
    @AppStorage(VoiceCoach.Keys.interval) private var intervalMeters = 1000.0
    @AppStorage(VoiceCoach.Keys.mode) private var mode = VoiceCoach.CueMode.distance.rawValue
    @AppStorage(VoiceCoach.Keys.intervalSeconds) private var intervalSeconds = 300
    @State private var coach = VoiceCoach()

    var body: some View {
        List {
            Group {
                Section {
                    Toggle("음성 안내", isOn: $isEnabled)
                } footer: {
                    Text("달리는 동안 거리·시간·페이스를 읽어줘요. 에어팟 등 연결된 이어폰으로 나오고, 음악은 안내 중 잠깐 작아져요.")
                }

                if isEnabled {
                    Section {
                        Picker("기준", selection: $mode) {
                            Text("거리").tag(VoiceCoach.CueMode.distance.rawValue)
                            Text("시간").tag(VoiceCoach.CueMode.time.rawValue)
                        }
                        .pickerStyle(.segmented)

                        if mode == VoiceCoach.CueMode.time.rawValue {
                            Picker("간격", selection: $intervalSeconds) {
                                Text("1분").tag(60)
                                Text("5분").tag(300)
                                Text("10분").tag(600)
                            }
                            .pickerStyle(.segmented)
                        } else {
                            Picker("간격", selection: $intervalMeters) {
                                Text("500m").tag(500.0)
                                Text("1km").tag(1000.0)
                                Text("2km").tag(2000.0)
                            }
                            .pickerStyle(.segmented)
                        }
                    } header: {
                        Text("안내 간격")
                    } footer: {
                        Text(mode == VoiceCoach.CueMode.time.rawValue
                             ? "정해진 시간마다 읽어줘요. 트랙처럼 거리가 잘 안 잡히는 곳에서 쓰기 좋아요."
                             : "정해진 거리를 지날 때마다 읽어줘요.")
                    }

                    Section {
                        Button("미리 듣기") {
                            coach.speak(VoiceCue.progress(distanceMeters: 1000, seconds: 372))
                        }
                        .foregroundStyle(.primary)
                    } footer: {
                        Text("더 자연스러운 음성을 원하면 iPhone 설정 → 손쉬운 사용 → 음성 콘텐츠 → 음성 → 한국어에서 '향상됨'을 내려받으면 자동으로 적용돼요.")
                    }
                }
            }
            .listRowBackground(Color.card)
        }
        .listStyle(.insetGrouped)
        .appListTone()
        .navigationTitle("음성 안내")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { VoiceSettingsView() }
}
