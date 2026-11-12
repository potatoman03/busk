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
    /// Focus set: the coach only cues this area, praising it when it's right.
    let focus: FormArea?
    /// Shots in the focus set; the coach calls the set done when it's reached (the player can keep going).
    let targetShots: Int?

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
    var summary: SessionSummary { SessionSummary(shots: shots, focus: focus) }
    var isDemo: Bool { source.isDemo }

    init(cameraView: CameraView, handedness: Handedness, source: PoseSource, voiceEnabled: Bool,
         ghostReplayEnabled: Bool = UserDefaults.standard.bool(forKey: SettingsKey.ghostReplay),
         focus: FormArea? = nil, targetShots: Int? = nil) {
        self.focus = focus
        self.targetShots = targetShots
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
                let ready = focus.map { "Got you. Focus on your \($0.title.lowercased()). Shoot when ready" } ?? "Got you. Shoot when ready"
                bannerText = ready
                speak(ready)
            } else if !visible && shots.isEmpty {
                bannerText = "Step back until you're in frame, head to feet"
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
            let cue = coachingCue(for: result)
            bannerText = cue
            speak(cue)
        }
        if analyzer.phase != phase {
            let next = analyzer.phase.rawValue, wrist = String(describing: frame[handedness.wrist])
            Self.analyzerLog.notice("t=\(frame.timestamp, format: .fixed(precision: 2)) phase \(next, privacy: .public) wrist=\(wrist, privacy: .public)")
        }
        phase = analyzer.phase
    }

    /// The cue for a shot. In a focus set it's about the focus area only. Either way, when the fix from the last shot
    /// got better the coach says so, and a cue repeated shot after shot changes its wording so it isn't one sentence on loop.
    private func coachingCue(for result: ShotResult) -> String {
        let previous = shots.dropLast().last
        var cue: String
        if let focus {
            let now = result.areas.first { $0.area == focus }
            switch now?.grade {
            case .good?: cue = focus.praise(shots.count)
            case .ok?: cue = "Closer. \(focus.cue)"
            case .needsWork?:
                cue = Self.improved(focus, from: previous, to: result) ? "Better that time. \(focus.cue)" : focus.cue
            case nil: cue = result.cue
            }
        } else if let fix = result.focus, Self.improved(fix, from: previous, to: result) {
            cue = "Better. \(result.cue)"
        } else if let prev = previous?.focus, prev != result.focus,
                  result.areas.first(where: { $0.area == prev })?.grade == .good {
            cue = "\(prev.title) fixed. Now: \(result.cue.prefix(1).lowercased() + result.cue.dropFirst())"
        } else {
            cue = result.cue
            let repeats = spokenLog.reversed().prefix { $0.text.hasSuffix(result.cue) }.count
            if repeats >= 2, let area = result.focus {
                cue = repeats % 2 == 0 ? "Still your \(area.title.lowercased()). \(result.cue)" : "Stay with it. \(result.cue)"
            }
        }
        if let focus, shots.count == targetShots, let r = summary.focusResult {
            cue += ". That's \(shots.count). \(r.good) of \(r.measured) good on your \(focus.title.lowercased()). Set done: keep going or tap End"
        }
        return cue
    }

    /// The area still needs work but is clearly less off than on the last shot.
    nonisolated static func improved(_ area: FormArea, from previous: ShotResult?, to result: ShotResult) -> Bool {
        guard let before = previous?.areas.first(where: { $0.area == area }),
              let now = result.areas.first(where: { $0.area == area }) else { return false }
        if now.grade > before.grade { return false }
        if now.grade < before.grade { return true }
        return before.severity > 0 && now.severity < before.severity * 0.75
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
