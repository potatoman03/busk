import SwiftData
import SwiftUI

struct LiveSessionView: View {
    @Bindable var session: CoachSession
    var onClose: () -> Void
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
            ZStack {
                Color.black.ignoresSafeArea()
                if let camera = session.source as? CameraPoseSource {
                    CameraPreview(source: camera).ignoresSafeArea()
                } else {
                    Theme.court.ignoresSafeArea()
                }
                SkeletonOverlay(pose: session.latestPose, handedness: session.handedness,
                                aspectRatio: session.source.aspectRatio, phase: session.phase)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    topBar
                    Spacer()
                    banner
                    if let shot = session.lastShot { ShotCard(shot: shot) }
                }
                .padding()
            }
            .onChange(of: geo.size, initial: true) { _, size in
                (session.source as? CameraPoseSource)?.setRotation(size.width > size.height ? 0 : 90)
            }
        }
        .statusBarHidden()
        .onDisappear { session.stop() }
    }

    private var topBar: some View {
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
        }
    }

    private var banner: some View {
        Text(session.bannerText)
            .font(.title2.bold())
            .multilineTextAlignment(.center)
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
    var body: some View {
        HStack(spacing: 14) {
            VStack {
                Text("\(shot.score)").font(.largeTitle.bold().monospacedDigit())
                    .foregroundStyle(Theme.color(forScore: shot.score))
                    .accessibilityIdentifier("lastShotScore")
                Text("form").font(.caption2).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(shot.areas) { a in
                    HStack(spacing: 6) {
                        Circle().fill(Theme.color(for: a.grade)).frame(width: 8, height: 8)
                        Text(a.area.title).font(.caption.bold())
                        Text(a.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
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
