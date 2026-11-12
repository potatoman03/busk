import SwiftUI

/// Launched with `-replay-keypoints PATH [-replay-label NAME]`: runs a live session on a recorded clip, so the shot
/// benchmark can show busk analysing each of its clips in the simulator.
/// With `-videoPath CLIP.mp4 [-handedness left] [-cameraView front]` it runs Vision on the video itself instead.
struct ReplaySessionView: View {
    var path: String?
    var video: URL?
    let label: String?
    @State private var session: CoachSession?
    @State private var error: String?
    @State private var replayed: ReplayStatus?

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
            if let replayed {
                Pill(text: "Replayed \(replayed.framesPlayed)/\(replayed.frames) frames · \(replayed.shots) shot\(replayed.shots == 1 ? "" : "s")",
                     systemImage: "checkmark.circle.fill")
                    .padding(.top, 152)
                    .accessibilityIdentifier("replayComplete")
            }
        }
        .task { load() }
    }

    init(path: String, label: String?) {
        self.path = path
        self.label = label
    }

    init(video: URL, label: String?) {
        self.video = video
        self.label = label
    }

    private func load() {
        guard session == nil else { return }
        if let video {
            let defaults = UserDefaults.standard
            let s = CoachSession(
                cameraView: CameraView(rawValue: defaults.string(forKey: SettingsKey.cameraView) ?? "") ?? .side,
                handedness: Handedness(rawValue: defaults.string(forKey: SettingsKey.handedness) ?? "") ?? .right,
                source: VideoPoseSource(url: video), voiceEnabled: defaults.object(forKey: SettingsKey.voiceEnabled) as? Bool ?? true)
            session = s
            s.start()
            return
        }
        guard let path else { return }
        do {
            let source = try ReplayPoseSource(contentsOf: URL(fileURLWithPath: path))
            let s = CoachSession(cameraView: source.clip.view, handedness: source.clip.handedness, source: source,
                                 voiceEnabled: UserDefaults.standard.object(forKey: SettingsKey.voiceEnabled) as? Bool ?? true)
            var status = ReplayStatus(label: label, path: path, frames: source.clip.frames.count)
            status.write()
            source.onFinished = { [weak source] in
                status.finished = true
                status.framesPlayed = source?.framesPlayed ?? 0
                status.shots = s.shots.count
                status.cues = s.spokenLog.map(\.text)
                status.write()
                replayed = status
            }
            session = s
            s.start()
        } catch {
            self.error = "Cannot read \(path): \(error.localizedDescription)"
        }
    }
}
