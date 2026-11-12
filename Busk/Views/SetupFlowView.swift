import SwiftUI

/// Pick camera angle and hand, check permission, then go live.
struct SetupFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.handedness) private var handedness: Handedness = .right
    @AppStorage(SettingsKey.cameraView) private var cameraView: CameraView = .side
    @AppStorage(SettingsKey.voiceEnabled) private var voiceEnabled = true
    @State private var session: CoachSession?
    @State private var cameraDenied = false
    @State private var finished: SessionSummary?
    @Environment(VoiceControl.self) private var voice: VoiceControl?
    /// Go live straight away (the player said "start session" on the home screen).
    var autoStart = false

    var body: some View {
        Group {
            if let session {
                LiveSessionView(session: session) {
                    session.stop()
                    self.session = nil
                    dismiss()
                }
            } else {
                setup
            }
        }
        .task {
            if autoStart && session == nil { await begin() }
        }
        .onChange(of: voice?.event) { _, event in
            if event?.command == .start && session == nil { Task { await begin() } }
        }
    }

    private var setup: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Card {
                        Text("Where is your phone?").font(.headline)
                        Picker("Camera angle", selection: $cameraView) {
                            ForEach(CameraView.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("cameraViewPicker")
                        Text(cameraView.hint).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Card {
                        Text("Shooting hand").font(.headline)
                        Picker("Shooting hand", selection: $handedness) {
                            ForEach(Handedness.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("handednessPicker")
                    }
                    Card {
                        Text("Setup checklist").font(.headline)
                        Label("Whole body in frame, head to feet", systemImage: "person.crop.rectangle")
                        Label("Phone steady on a tripod or against the pole", systemImage: "camera.on.rectangle")
                        Label("Volume up, or AirPods in", systemImage: "speaker.wave.2")
                        Label("Good light, sun behind the phone", systemImage: "sun.max")
                    }
                    .font(.subheadline)
                    if cameraDenied {
                        Card {
                            Label("Camera access is off", systemImage: "exclamationmark.triangle").foregroundStyle(.yellow)
                            Text("Turn on camera access for Busk in Settings to track your shot.").font(.footnote)
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }
                        }
                    }
                    Button {
                        Task { await begin() }
                    } label: {
                        Text(AppEnvironment.forceDemo ? "Start demo session" : "Go live")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("goLiveButton")
                    if AppEnvironment.forceDemo {
                        Text("No camera here, so a demo shooter will take shots for you.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .background(Theme.court.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { VoiceControlBar(commands: [.start]).padding(.bottom, 4) }
            .navigationTitle("Set up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("cancelSetupButton")
                }
            }
        }
    }

    private func begin() async {
        guard session == nil else { return }
        let source: PoseSource
        if AppEnvironment.forceDemo || !CameraPoseSource.isAvailable {
            source = DemoPoseSource(handedness: handedness, view: cameraView, leadIn: AppEnvironment.demoIdle ? 120 : 0.5)
        } else {
            guard await CameraPoseSource.requestAccess() else {
                cameraDenied = true
                return
            }
            source = CameraPoseSource()
        }
        let s = CoachSession(cameraView: cameraView, handedness: handedness, source: source,
                             voiceEnabled: voiceEnabled && !AppEnvironment.isUITesting)
        session = s
        s.start()
    }
}
