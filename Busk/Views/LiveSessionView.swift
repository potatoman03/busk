import SwiftData
import SwiftUI

struct LiveSessionView: View {
    @Bindable var session: CoachSession
    var onClose: () -> Void
    /// Extra status pills (e.g. the replay clip label) shown under the phase pill, so they never cover the cue.
    var badges: AnyView? = nil
    @Environment(\.modelContext) private var modelContext
    @State private var ended = false

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
                        Image(decorative: image, scale: 1).resizable().scaledToFit()
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
                SkeletonOverlay(pose: (session.source as? VideoPoseSource)?.currentImagePose ?? session.latestPose, handedness: session.handedness,
                                aspectRatio: session.source.aspectRatio, centerX: session.source.displayCenterX,
                                phase: session.phase, fill: session.source is CameraPoseSource)
                    .padding(.trailing, poseInset)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    topBar(showBadges: !landscape)
                    if landscape {
                        HStack(alignment: .top, spacing: 16) {
                            // Badges share the left column with the ghost replay, so they never add height above the cue column.
                            VStack(alignment: .leading, spacing: 8) {
                                if let badges { badges }
                                replayPanel
                            }
                            VStack(spacing: 12) {
                                Spacer(minLength: 0)
                                feedback(compact: true)
                            }
                            .frame(width: hudWidth)
                        }
                    } else {
                        replayPanel
                        feedback(compact: false)
                    }
                }
                .padding()
            }
        }
        .statusBarHidden()
        .onDisappear { session.stop() }
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
                    banner(compact: compact)
                    if AppEnvironment.showSpokenCues, let cue = session.spokenLog.last {
                        Label("\(cue.muted ? "Muted" : "Said") #\(session.spokenLog.count): \(cue.text)",
                              systemImage: cue.muted ? "speaker.slash" : "waveform")
                            .font(.caption.monospaced())
                            .lineLimit(compact ? 2 : 1)
                            .fixedSize(horizontal: false, vertical: compact)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .accessibilityIdentifier("lastSpokenCue")
                    }
                    if let shot = session.lastShot { ShotCard(shot: shot, compact: compact) }
    }

    private func topBar(showBadges: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 10) {
            Button {
                session.stop()
                if !session.shots.isEmpty {
                    modelContext.insert(SessionRecord(date: session.startDate, duration: Date().timeIntervalSince(session.startDate),
                                                      view: session.cameraView, handedness: session.handedness,
                                                      isDemo: session.isDemo, shots: session.shots))
                    try? modelContext.save()
                    ended = true
                } else {
                    onClose()
                }
            } label: {
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
            Pill(text: session.phase.rawValue, systemImage: session.bodyVisible ? "figure.stand" : "person.slash")
                .accessibilityIdentifier("phaseLabel")
            if showBadges, let badges { badges }
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
    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.bold())
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

struct ShotCard: View {
    let shot: ShotResult
    /// The landscape side column is short, so show fewer, single-line areas there.
    var compact = false
    var body: some View {
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
                        Text(a.detail).font(.caption).foregroundStyle(.secondary).lineLimit(compact ? 1 : 2).fixedSize(horizontal: false, vertical: !compact)
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
