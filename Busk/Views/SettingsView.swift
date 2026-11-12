import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.voiceEnabled) private var voiceEnabled = true
    @AppStorage(SettingsKey.handedness) private var handedness: Handedness = .right
    @AppStorage(SettingsKey.cameraView) private var cameraView: CameraView = .side

    var body: some View {
        NavigationStack {
            Form {
                Section("Coach") {
                    Toggle("Spoken feedback", isOn: $voiceEnabled).accessibilityIdentifier("voiceSetting")
                    Button("Test voice") { CoachVoice.preview.say("Tuck your elbow under the ball") }
                        .disabled(!voiceEnabled)
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
