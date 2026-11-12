import Foundation
import Observation
import OSLog

/// Runs one coaching session: pose frames in, shots and spoken cues out.
@MainActor
@Observable
final class CoachSession {
    let cameraView: CameraView
    let handedness: Handedness
    let source: PoseSource
    let startDate = Date()

    private(set) var latestPose: PoseFrame?
    private(set) var shots: [ShotResult] = []
    private(set) var phase: ShotPhase = .waiting
    private(set) var bannerText = "Step into frame"
    private(set) var bodyVisible = false
    /// Every cue the coach said (or would have said while muted), newest last.
    private(set) var spokenLog: [SpokenCue] = []

    var voiceEnabled: Bool {
        didSet { voice.enabled = voiceEnabled }
    }
    /// Show a slow-motion replay after each shot with the session's best shot as a ghost.
    let ghostReplayEnabled: Bool
    private(set) var replay: ShotReplay?

    @ObservationIgnored private let analyzer: ShotAnalyzer
    @ObservationIgnored private let evaluator = FormEvaluator()
    @ObservationIgnored let voice = CoachVoice()
    @ObservationIgnored private var lastSeen: TimeInterval = 0
    @ObservationIgnored private var lastFrameTime: TimeInterval = 0
    @ObservationIgnored private var announcedVisible = false
    @ObservationIgnored private var statusUntil = Date.distantPast
    @ObservationIgnored private var best: (clip: ShotClip, number: Int, score: Int)?

    var lastShot: ShotResult? { shots.last }
    var summary: SessionSummary { SessionSummary(shots: shots) }
    var isDemo: Bool { source.isDemo }

    init(cameraView: CameraView, handedness: Handedness, source: PoseSource, voiceEnabled: Bool,
         ghostReplayEnabled: Bool = UserDefaults.standard.bool(forKey: SettingsKey.ghostReplay)) {
        self.ghostReplayEnabled = ghostReplayEnabled
        self.cameraView = cameraView
        self.handedness = handedness
        self.source = source
        self.voiceEnabled = voiceEnabled
        analyzer = ShotAnalyzer(handedness: handedness, view: cameraView)
        voice.enabled = voiceEnabled
    }

    func start() {
        voice.prepareAudioSession()
        source.onFrame = { [weak self] frame in
            MainActor.assumeIsolated { self?.handle(frame) }
        }
        source.start()
    }

    func stop() {
        source.stop()
        source.onFrame = nil
        voice.stop()
    }

    func handle(_ frame: PoseFrame) {
        lastFrameTime = frame.timestamp
        let visible = [handedness.shoulder, handedness.elbow, handedness.wrist].allSatisfy { frame[$0] != nil }
        if visible {
            latestPose = frame
            lastSeen = frame.timestamp
        } else if frame.timestamp - lastSeen > 0.5 {
            latestPose = frame.joints.isEmpty ? nil : frame
        }
        if visible != bodyVisible {
            bodyVisible = visible
            if visible && !announcedVisible {
                announcedVisible = true
                bannerText = "Got you. Shoot when ready"
                speak("Got you. Shoot when ready")
            } else if !visible && shots.isEmpty {
                bannerText = "Step into frame"
            }
        }

        if let metrics = analyzer.process(frame) {
            let result = evaluator.evaluate(metrics)
            if let json = try? JSONEncoder().encode(metrics), let text = String(data: json, encoding: .utf8) {
                Self.log.notice("shot #\(self.shots.count + 1, privacy: .public) metrics: \(text, privacy: .public)")
            }
            shots.append(result)
            if let clip = analyzer.lastShotClip {
                if ghostReplayEnabled {
                    replay = ShotReplay(shot: clip, number: shots.count, score: result.score, best: best)
                }
                if result.score > best?.score ?? -1 { best = (clip, shots.count, result.score) }
            }
            bannerText = result.cue
            speak(result.cue)
        }
        if analyzer.phase != phase {
            let next = analyzer.phase.rawValue, wrist = String(describing: frame[handedness.wrist])
            Self.analyzerLog.notice("t=\(frame.timestamp, format: .fixed(precision: 2)) phase \(next, privacy: .public) wrist=\(wrist, privacy: .public)")
        }
        phase = analyzer.phase
    }

    func dismissReplay(_ id: ShotReplay.ID) {
        if replay?.id == id { replay = nil }
    }

    /// Answers "how am I doing": a spoken summary of the session so far, even when the coach is muted.
    func speakStatus() {
        let text = summary.spokenStatus
        statusUntil = Date().addingTimeInterval(max(2, Double(text.split(separator: " ").count) * 0.4))
        speak(text, force: true)
    }

    private func speak(_ text: String, force: Bool = false) {
        // Shot cues don't talk over (or cut off) the answer to "how am I doing"; the banner and shot card still update.
        if !force && Date() < statusUntil {
            Self.log.notice("skipped cue during status answer: \(text, privacy: .public)")
            return
        }
        let cue = SpokenCue(text: text, muted: !voiceEnabled && !force)
        spokenLog.append(cue)
        Self.log.notice("\(cue.muted ? "muted" : "spoken", privacy: .public) cue #\(self.spokenLog.count, privacy: .public): \(text, privacy: .public)")
        voice.say(text, force: force)
    }

    private static let log = Logger(subsystem: "com.potatoman03.busk", category: "voice")
    private static let analyzerLog = Logger(subsystem: "com.potatoman03.busk", category: "analyzer")
}

struct SpokenCue: Equatable {
    let text: String
    let muted: Bool
}
