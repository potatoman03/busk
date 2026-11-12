import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.voiceEnabled) private var voiceEnabled = true
    @AppStorage(SettingsKey.voiceCommands) private var voiceCommands = false
    @AppStorage(SettingsKey.handedness) private var handedness: Handedness = .right
    @AppStorage(SettingsKey.cameraView) private var cameraView: CameraView = .side
    @AppStorage(SettingsKey.ghostReplay) private var ghostReplay = false
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [SessionRecord]
    @State private var confirmDelete = false
    @State private var speaking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Spoken feedback", isOn: $voiceEnabled).accessibilityIdentifier("voiceSetting")
                    Button {
                        CoachVoice.configureAudioSession()
                        CoachVoice.preview.say("Tuck your elbow under the ball")
                        speaking = true
                        Task {
                            try? await Task.sleep(for: .seconds(2.5))
                            speaking = false
                        }
                    } label: {
                        HStack {
                            Text("Test voice")
                            Spacer()
                            if speaking {
                                Label("Speaking", systemImage: "speaker.wave.2.fill")
                                    .font(.footnote).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("testVoiceSpeaking")
                            }
                        }
                    }
                    .disabled(!voiceEnabled)
                    .accessibilityIdentifier("testVoiceButton")
                } header: {
                    Text("Coach")
                } footer: {
                    Text("Cues play even with the silent switch on. Turn the volume up or put AirPods in if you can't hear them.")
                }
                Section {
                    Toggle("Voice commands", isOn: $voiceCommands).accessibilityIdentifier("voiceCommandsSetting")
                    Toggle("Ghost replay", isOn: $ghostReplay).accessibilityIdentifier("ghostReplaySetting")
                } header: {
                    Text("Extras")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Voice commands: from the shooting spot, say “start session”, “how am I doing” or “end session”. Speech is recognized on your phone; Busk asks for the microphone when you turn this on.")
                        Text("Ghost replay: after each shot, replays it in slow motion with your best shot of the session drawn over it, lined up at the release.")
                    }
                }
                Section("Defaults") {
                    Picker("Shooting hand", selection: $handedness) {
                        ForEach(Handedness.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Camera angle", selection: $cameraView) {
                        ForEach(CameraView.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section {
                    Button("Delete all sessions", role: .destructive) { confirmDelete = true }
                        .disabled(records.isEmpty)
                        .accessibilityIdentifier("deleteAllSessionsButton")
                } header: {
                    Text("Your data")
                } footer: {
                    Text(records.isEmpty ? "No sessions saved yet."
                         : "\(records.count) \(records.count == 1 ? "session" : "sessions") saved on this phone.")
                }
                .confirmationDialog("Delete all \(records.count) \(records.count == 1 ? "session" : "sessions")? This can't be undone.",
                                    isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete all sessions", role: .destructive) {
                        records.forEach(modelContext.delete)
                        try? modelContext.save()
                    }
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.versionString)
                    Text("Busk tracks your body with Apple's on-device Vision framework. Video stays on your phone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("settingsDoneButton")
                }
            }
        }
    }
}

extension CoachVoice {
    static let preview = CoachVoice()
}

extension Bundle {
    var versionString: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
