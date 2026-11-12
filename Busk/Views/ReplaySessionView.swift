import SwiftUI

/// Launched with `-replay-keypoints PATH [-replay-label NAME]`: runs a live session on a recorded clip, so the shot
/// benchmark can show busk analysing each of its clips in the simulator.
struct ReplaySessionView: View {
    let path: String
    let label: String?
    @State private var session: CoachSession?
    @State private var error: String?

    var body: some View {
        ZStack(alignment: .top) {
            if let session {
                LiveSessionView(session: session) { session.stop() }
            } else {
                Theme.court.ignoresSafeArea()
                Text(error ?? "Loading clip").foregroundStyle(.secondary).padding(.top, 200)
            }
            if let label {
                Pill(text: "Benchmark clip: \(label)", systemImage: "film")
                    .padding(.top, 116)
                    .accessibilityIdentifier("replayClipLabel")
            }
        }
        .task { load() }
    }

    private func load() {
        guard session == nil else { return }
        do {
            let source = try ReplayPoseSource(contentsOf: URL(fileURLWithPath: path))
            let s = CoachSession(cameraView: source.clip.view, handedness: source.clip.handedness, source: source,
                                 voiceEnabled: false)
            session = s
            s.start()
        } catch {
            self.error = "Cannot read \(path): \(error.localizedDescription)"
        }
    }
}
