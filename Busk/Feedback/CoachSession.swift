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

    @ObservationIgnored private let analyzer: ShotAnalyzer
    @ObservationIgnored private let evaluator = FormEvaluator()
    @ObservationIgnored let voice = CoachVoice()
    @ObservationIgnored private var lastSeen: TimeInterval = 0
    @ObservationIgnored private var lastFrameTime: TimeInterval = 0
    @ObservationIgnored private var announcedVisible = false

    var lastShot: ShotResult? { shots.last }
    var summary: SessionSummary { SessionSummary(shots: shots) }
    var isDemo: Bool { source.isDemo }

    init(cameraView: CameraView, handedness: Handedness, source: PoseSource, voiceEnabled: Bool) {
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
            bannerText = result.cue
            speak(result.cue)
        }
        phase = analyzer.phase
    }

    private func speak(_ text: String) {
        let cue = SpokenCue(text: text, muted: !voiceEnabled)
        spokenLog.append(cue)
        Self.log.notice("\(cue.muted ? "muted" : "spoken", privacy: .public) cue #\(self.spokenLog.count, privacy: .public): \(text, privacy: .public)")
        voice.say(text)
    }

    private static let log = Logger(subsystem: "com.potatoman03.busk", category: "voice")
}

struct SpokenCue: Equatable {
    let text: String
    let muted: Bool
}
