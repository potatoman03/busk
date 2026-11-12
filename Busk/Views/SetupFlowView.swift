import SwiftUI

/// Pick camera angle and hand, check permission, then go live.
struct SetupFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.handedness) private var handedness: Handedness = .right
    @AppStorage(SettingsKey.cameraView) private var cameraView: CameraView = .side
    @AppStorage(SettingsKey.voiceEnabled) private var voiceEnabled = true
    @State private var session: CoachSession?
    @State private var cameraDenied = false
    @State private var starting = false
    @State private var finished: SessionSummary?
    @Environment(VoiceControl.self) private var voice: VoiceControl?
    /// Go live straight away (the player said "start session" on the home screen).
    var autoStart = false
    /// Focus set from the coaching plan: the coach only cues this area.
    var focus: FormArea? = nil
    var targetShots: Int? = nil

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
            if let view = focus?.bestView { cameraView = view }
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
                    if let focus {
                        Card {
                            Label("Focus set", systemImage: "scope").font(.caption).foregroundStyle(.secondary)
                            Text(focus.title + (targetShots.map { " · \($0) shots" } ?? "")).font(.title3.bold())
                            Text("Busk only coaches your \(focus.title.lowercased()) this set: \(focus.cue.lowercased()).")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if let view = focus.bestView {
                                Label("\(focus.title) is judged with the phone \(view == .front ? "facing you" : "side on")",
                                      systemImage: "camera.viewfinder")
                                    .font(.footnote).foregroundStyle(cameraView == view ? Color.secondary : Color.yellow)
                            }
                        }
                        .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("setupFocusCard")
                    }
                    Card {
                        Text("Where is your phone?").font(.headline)
                        Picker("Camera angle", selection: $cameraView) {
                            ForEach(CameraView.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("cameraViewPicker")
                        PhonePlacementDiagram(view: cameraView, handedness: handedness)
                            .frame(height: 150)
                        Text(cameraView.hint).font(.subheadline).foregroundStyle(.secondary)
                        Text("Checks " + FormArea.allCases.filter { $0.bestView == nil || $0.bestView == cameraView }
                            .map { $0.title.lowercased() }.formatted(.list(type: .and)) + ".")
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("cameraViewChecks")
                        if focus == nil {
                            Label("New to this? Start with Facing me: it checks your elbow and guide hand, the most common beginner misses. Side on checks your arc.",
                                  systemImage: "lightbulb")
                                .font(.footnote).foregroundStyle(Theme.orange)
                        }
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
        guard session == nil, !starting else { return }
        starting = true
        defer { starting = false }
        let source: PoseSource
        if AppEnvironment.forceDemo || !CameraPoseSource.isAvailable {
            source = DemoPoseSource(handedness: handedness, view: cameraView, leadIn: AppEnvironment.demoIdle ? 120 : 0.5,
                                    walkIn: AppEnvironment.demoWalkIn)
        } else {
            guard await CameraPoseSource.requestAccess() else {
                cameraDenied = true
                return
            }
            source = CameraPoseSource()
        }
        let s = CoachSession(cameraView: cameraView, handedness: handedness, source: source,
                             voiceEnabled: voiceEnabled && !AppEnvironment.isUITesting, focus: focus, targetShots: targetShots)
        session = s
        s.start()
    }
}

/// Top-down sketch of where the phone goes for each camera angle: shooter, hoop, phone and the 3-4 m gap.
struct PhonePlacementDiagram: View {
    let view: CameraView
    let handedness: Handedness

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let player = CGPoint(x: w / 2, y: h * 0.78)
            let hoop = CGPoint(x: w / 2, y: h * 0.1)
            let side: CGFloat = handedness == .right ? 1 : -1
            let phone = view == .side
                ? CGPoint(x: w / 2 + side * min(w * 0.36, 130), y: player.y)
                : CGPoint(x: w / 2 + side * 18, y: h * 0.3)
            let secondary = GraphicsContext.Shading.color(.secondary)

            var rim = Path()
            rim.move(to: CGPoint(x: hoop.x - 22, y: hoop.y - 6))
            rim.addLine(to: CGPoint(x: hoop.x + 22, y: hoop.y - 6))
            ctx.stroke(rim, with: secondary, lineWidth: 3)
            ctx.stroke(Path(ellipseIn: CGRect(x: hoop.x - 9, y: hoop.y - 4, width: 18, height: 12)), with: .color(Theme.orange), lineWidth: 2)
            ctx.draw(Text("Hoop").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: hoop.x + 44, y: hoop.y))

            var shot = Path()
            shot.move(to: CGPoint(x: player.x, y: player.y - 18))
            shot.addLine(to: CGPoint(x: hoop.x, y: hoop.y + 16))
            ctx.stroke(shot, with: .color(Theme.orange.opacity(0.5)), style: StrokeStyle(lineWidth: 2, dash: [2, 5]))

            ctx.fill(Path(ellipseIn: CGRect(x: player.x - 12, y: player.y - 12, width: 24, height: 24)), with: .color(.white))
            ctx.draw(Text("You").font(.caption.bold()).foregroundStyle(.white), at: CGPoint(x: player.x, y: player.y + 24))

            var gap = Path()
            gap.move(to: phone)
            gap.addLine(to: player)
            ctx.stroke(gap, with: secondary, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            let mid = CGPoint(x: (phone.x + player.x) / 2, y: (phone.y + player.y) / 2)
            let labelOffset: CGPoint = view == .side ? CGPoint(x: 0, y: -12) : CGPoint(x: side * 34, y: 0)
            ctx.draw(Text("3-4 m").font(.caption2.bold()).foregroundStyle(.secondary),
                     at: CGPoint(x: mid.x + labelOffset.x, y: mid.y + labelOffset.y))

            let body = CGRect(x: phone.x - 9, y: phone.y - 14, width: 18, height: 28)
            ctx.fill(Path(roundedRect: body, cornerRadius: 4), with: .color(Theme.orange))
            ctx.draw(Text("Phone").font(.caption.bold()).foregroundStyle(Theme.orange),
                     at: view == .side ? CGPoint(x: phone.x, y: phone.y + 26) : CGPoint(x: phone.x + side * 40, y: phone.y))
        }
        .accessibilityElement()
        .accessibilityLabel(view == .side
            ? "Diagram: phone 3 to 4 metres to your shooting side, waist high"
            : "Diagram: phone 3 to 4 metres in front of you, between you and the hoop, waist high")
        .accessibilityIdentifier("phonePlacementDiagram")
    }
}
