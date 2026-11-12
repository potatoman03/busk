import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.voiceEnabled) private var voiceEnabled = true
    @AppStorage(SettingsKey.voiceCommands) private var voiceCommands = false
    @AppStorage(SettingsKey.handedness) private var handedness: Handedness = .right
    @AppStorage(SettingsKey.cameraView) private var cameraView: CameraView = .side
    @AppStorage(SettingsKey.ghostReplay) private var ghostReplay = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Coach") {
                    Toggle("Spoken feedback", isOn: $voiceEnabled).accessibilityIdentifier("voiceSetting")
                    Button("Test voice") { CoachVoice.preview.say("Tuck your elbow under the ball") }
                        .disabled(!voiceEnabled)
                }
                Section {
                    Toggle("Voice commands", isOn: $voiceCommands).accessibilityIdentifier("voiceCommandsSetting")
                    Toggle("Ghost replay", isOn: $ghostReplay).accessibilityIdentifier("ghostReplaySetting")
                } header: {
                    Text("Prototype")
                } footer: {
                    Text("Voice commands: from the shooting spot, say “start session”, “how am I doing” or “end session”. Speech is recognized on your phone; Busk asks for the microphone when you turn this on.
Ghost replay: after each shot, replays it in slow motion with your best shot of the session drawn over it, lined up at the release.")
                }
                Section("Defaults") {
                    Picker("Shooting hand", selection: $handedness) {
                        ForEach(Handedness.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Camera angle", selection: $cameraView) {
                        ForEach(CameraView.allCases) { Text($0.label).tag($0) }
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
