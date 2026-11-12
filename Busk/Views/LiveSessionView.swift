import SwiftData
import SwiftUI

struct LiveSessionView: View {
    @Bindable var session: CoachSession
    var onClose: () -> Void
    /// Extra status pills (e.g. the replay clip label) shown under the phase pill, so they never cover the cue.
    var badges: AnyView? = nil
    @Environment(\.modelContext) private var modelContext
    @State private var ended = false
    @Environment(VoiceControl.self) private var voice: VoiceControl?

    var body: some View {
        if ended {
            NavigationStack {
                SummaryContent(summary: session.summary, date: session.startDate, isDemo: session.isDemo)
                    .navigationTitle("Session summary")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", action: onClose).accessibilityIdentifier("summaryDoneButton")
                        }
                    }
            }
        } else {
            live
        }
    }

    private var skeleton: some View {
        SkeletonOverlay(pose: (session.source as? VideoPoseSource)?.currentImagePose ?? session.latestPose, handedness: session.handedness,
                        aspectRatio: session.source.aspectRatio, centerX: session.source.displayCenterX,
                        phase: session.phase, fill: session.source is CameraPoseSource)
    }

    private var live: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let hudWidth = landscape ? min(380, geo.size.width * 0.45) : 0
            // In landscape the cue and form card sit in a right-hand column so they never cover the shooter.
            let poseInset = session.source is CameraPoseSource ? 0 : hudWidth
            ZStack {
                Color.black.ignoresSafeArea()
                if let camera = session.source as? CameraPoseSource {
                    CameraPreview(source: camera).ignoresSafeArea()
                } else if let video = session.source as? VideoPoseSource {
                    Theme.court.ignoresSafeArea()
                    if let image = video.currentImage {
                        // The skeleton is drawn on the picture itself so both share one frame in every orientation.
                        Image(decorative: image, scale: 1).resizable().scaledToFit()
                            .overlay { skeleton }
                            .padding(.trailing, poseInset).ignoresSafeArea()
                    }
                    if video.visionUnavailable {
                        Text("Vision body pose isn't available here. Run scripts/vision-keypoints.swift on the clip to make a keypoints file.")
                            .font(.footnote).multilineTextAlignment(.center).padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 24)
                            .accessibilityIdentifier("visionUnavailable")
                    }
                } else {
                    Theme.court.ignoresSafeArea()
                }
                if (session.source as? VideoPoseSource)?.currentImage == nil {
                    skeleton
                        .padding(.trailing, poseInset)
                        .ignoresSafeArea()
                }
                VStack(spacing: 12) {
                    topBar(landscape: landscape)
                    if landscape {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                replayPanel
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            VStack(spacing: 12) {
                                Spacer(minLength: 0)
                                framingCard
                                feedback(compact: true)
                            }
                            .frame(width: hudWidth)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        replayPanel
                        framingCard
                        feedback(compact: false)
                    }
                }
                .padding()
            }
        }
        .statusBarHidden()
        .onDisappear { session.stop() }
        .onChange(of: voice?.event) { _, event in
            guard !ended else { return }
            switch event?.command {
            case .end: endSession()
            case .status: session.speakStatus()
            case .start, nil: break
            }
        }
    }

    private func endSession() {
        session.stop()
        if !session.shots.isEmpty {
            modelContext.insert(SessionRecord(date: session.startDate, duration: Date().timeIntervalSince(session.startDate),
                                              view: session.cameraView, handedness: session.handedness,
                                              isDemo: session.isDemo, shots: session.shots, focus: session.focus))
            try? modelContext.save()
            ended = true
        } else {
            onClose()
        }
    }

    @ViewBuilder private var replayPanel: some View {
        if let replay = session.replay {
            GhostReplayView(replay: replay, handedness: session.handedness) { session.dismissReplay(replay.id) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        } else {
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func feedback(compact: Bool) -> some View {
        if compact, let voice, voice.state != .off {
            // The landscape column is short: when a long cue leaves no room for the voice bar, drop the spoken-cue
            // log, then shrink the form card to its score, so the cue, the score and the voice buttons stay whole.
            ViewThatFits(in: .vertical) {
                feedbackStack(compact: true, cueLog: true, card: .full)
                feedbackStack(compact: true, cueLog: false, card: .full)
                feedbackStack(compact: true, cueLog: false, card: .scoreOnly)
            }
        } else {
            feedbackStack(compact: compact, cueLog: true, card: .full)
        }
    }

    private func feedbackStack(compact: Bool, cueLog: Bool, card: ShotCard.Style) -> some View {
        VStack(spacing: 12) {
                    banner(compact: compact)
                    if cueLog, AppEnvironment.showSpokenCues, let cue = session.spokenLog.last {
                        Label("\(cue.muted ? "Muted" : "Said") #\(session.spokenLog.count): \(cue.text)",
                              systemImage: cue.muted ? "speaker.slash" : "waveform")
                            .font(.caption.monospaced())
                            .lineLimit(compact ? 2 : 1)
                            .fixedSize(horizontal: false, vertical: compact)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .accessibilityIdentifier("lastSpokenCue")
                    }
                    if let shot = session.lastShot { ShotCard(shot: shot, compact: compact, style: card) }
                    VoiceControlBar(commands: [.status, .end], compact: compact)
        }
    }

    private var phasePill: some View {
        HStack(spacing: 8) {
            Pill(text: session.phase.rawValue, systemImage: session.bodyVisible ? "figure.stand" : "person.slash")
                .accessibilityIdentifier("phaseLabel")
            if let focus = session.focus, let r = session.summary.focusResult {
                Pill(text: "\(focus.title) \(r.good)/\(r.measured)" + (session.targetShots.map { session.shots.count >= $0 ? " · set done" : " · set \(session.shots.count)/\($0)" } ?? ""),
                     systemImage: "scope")
                    .accessibilityIdentifier("focusPill")
            }
        }
    }

    private func topBar(landscape: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 10) {
            Button(action: endSession) {
                Label("End", systemImage: "stop.fill").font(.headline).lineLimit(1).fixedSize()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .accessibilityIdentifier("endSessionButton")

            Spacer()
            if session.isDemo {
                Pill(text: "Demo", systemImage: "play.rectangle").accessibilityIdentifier("demoBadge")
            }
            VStack(spacing: 0) {
                Text("\(session.shots.count)").font(.title2.bold().monospacedDigit())
                    .accessibilityIdentifier("shotCount")
                Text("shots").font(.caption2)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            Button {
                session.voiceEnabled.toggle()
            } label: {
                Image(systemName: session.voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(session.voiceEnabled ? "Mute coach" : "Unmute coach")
            .accessibilityIdentifier("voiceToggle")
        }
            if landscape {
                // One row beside the phase pill, so badges add no height and stay above the shooter.
                HStack(spacing: 8) {
                    phasePill
                    if let badges { badges }
                }
            } else {
                phasePill
                if let badges { badges }
            }
        }
    }

    /// Before the first shot: what the camera can and can't see, so the player can fix the setup.
    @ViewBuilder private var framingCard: some View {
        if let f = session.framing {
            HStack(spacing: 14) {
                ForEach([("Head", f.head), ("Shooting arm", f.arm), ("Feet", f.feet), ("Centred", f.centred)], id: \.0) { item in
                    Label(item.0, systemImage: item.1 ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(item.1 ? Color.green : Color.yellow)
                }
            }
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("framingCheck")
        }
    }

    private func banner(compact: Bool) -> some View {
        Text(session.bannerText)
            .font(compact ? .title3.bold() : .title2.bold())
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.orange.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityIdentifier("cueBanner")
            .animation(.snappy, value: session.bannerText)
    }
}

struct Pill: View {
    let text: String
    let systemImage: String
    /// Long labels shorten in the middle instead of widening the layout.
    var truncates = false
    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.bold())
            .lineLimit(1)
            .truncationMode(.middle)
            .fixedSize(horizontal: !truncates, vertical: true)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

struct ShotCard: View {
    let shot: ShotResult
    /// The landscape side column is short, so show fewer, single-line areas there.
    var compact = false
    enum Style { case full, scoreOnly }
    /// `scoreOnly` keeps the score and the weakest area on one row for when the column has no room for more.
    var style = Style.full
    var body: some View {
        switch style {
        case .full: fullCard
        case .scoreOnly: scoreRow
        }
    }

    private var scoreRow: some View {
        HStack(spacing: 10) {
            Text("\(shot.score)").font(.title2.bold().monospacedDigit())
                .foregroundStyle(Theme.color(forScore: shot.score))
                .accessibilityIdentifier("lastShotScore")
            Text("form").font(.caption2).foregroundStyle(.secondary)
            if let worst = shot.areas.max(by: { $0.grade < $1.grade }) {
                Circle().fill(Theme.color(for: worst.grade)).frame(width: 8, height: 8)
                Text(worst.area.title).font(.caption.bold())
                Text(worst.plain).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lastShotCard")
    }

    private var fullCard: some View {
        HStack(spacing: 14) {
            VStack {
                Text("\(shot.score)").font(.largeTitle.bold().monospacedDigit())
                    .foregroundStyle(Theme.color(forScore: shot.score))
                    .accessibilityIdentifier("lastShotScore")
                Text("form").font(.caption2).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(shot.areas.sorted { $0.grade > $1.grade }.prefix(compact ? 3 : 4)) { a in
                    HStack(spacing: 6) {
                        Circle().fill(Theme.color(for: a.grade)).frame(width: 8, height: 8)
                        Text(a.area.title).font(.caption.bold())
                        Text(a.plain).font(.caption).foregroundStyle(.secondary).lineLimit(compact ? 1 : 2).fixedSize(horizontal: false, vertical: !compact)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lastShotCard")
    }
}
