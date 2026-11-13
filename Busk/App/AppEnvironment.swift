import Foundation

enum AppEnvironment {
    static let arguments = ProcessInfo.processInfo.arguments
    static var isUITesting: Bool { arguments.contains("-ui-testing") }
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    /// Use the synthetic shooter instead of the camera.
    static var forceDemo: Bool { isUITesting || isSimulator || arguments.contains("-demo") }
    /// `-demo-idle`: the demo shooter stands still for two minutes before shooting (UI tests that need no shots).
    static var demoIdle: Bool { arguments.contains("-demo-idle") }
    /// `-hold-voice-preview`: Settings' Test voice stays "Speaking" until stopped instead of playing (UI tests on slow simulators).
    static var holdVoicePreview: Bool { isUITesting && arguments.contains("-hold-voice-preview") }
    /// `-demo-walk-in`: the demo shooter starts badly framed (off to the side, too close, feet cut off) so the framing check shows.
    static var demoWalkIn: Bool { arguments.contains("-demo-walk-in") }
    /// Demo shots stay out of the coaching plan, except in UI tests or with `-demo-counts` (simulator checks of the plan).
    static var demoCountsForPlan: Bool { isUITesting || arguments.contains("-demo-counts") }
    /// `-videoPath /path/clip.mp4` runs Vision on a video file instead of the camera or demo shooter.
    static var videoURL: URL? {
        UserDefaults.standard.string(forKey: "videoPath").map { URL(fileURLWithPath: $0) }
    }
    /// Shows a record of every spoken cue on screen (simulator, UI tests, or `-showSpokenCues`).
    static var showSpokenCues: Bool { isUITesting || isSimulator || arguments.contains("-showSpokenCues") }
    /// Benchmark: replay this keypoint file in a live session instead of showing the home screen.
    /// No microphone in the simulator or UI tests: voice commands come from on-screen buttons (`-simulateVoice` forces this).
    static var simulateVoiceInput: Bool { isUITesting || isSimulator || arguments.contains("-simulateVoice") }
    static var replayKeypointsPath: String? { value(after: "-replay-keypoints") }
    /// `-seed-practice N`: fills History with N days of sample sessions (UI tests and screenshots only).
    static var seedPracticeDays: Int? { isUITesting ? value(after: "-seed-practice").flatMap(Int.init) : nil }
    static var replayLabel: String? { value(after: "-replay-label") }
    static var replayStatusPath: String? { value(after: "-replay-status") }

    private static func value(after flag: String) -> String? {
        guard let i = arguments.firstIndex(of: flag), arguments.indices.contains(i + 1) else { return nil }
        return arguments[i + 1]
    }
}

enum SettingsKey {
    static let voiceEnabled = "voiceEnabled"
    static let handedness = "handedness"
    static let cameraView = "cameraView"
    static let ghostReplay = "ghostReplay"
    static let hasSeenSetupTips = "hasSeenSetupTips"
    /// Prototype, off by default; `-voiceCommands YES` turns it on for simulator runs.
    static let voiceCommands = "voiceCommands"
    /// Whether the player has a ball; without one the coaching plan uses shadow shots and ball-free drills.
    static let hasBall = "hasBall"
    /// Shots a day the practice tracker counts toward.
    static let dailyShotGoal = "dailyShotGoal"
}
