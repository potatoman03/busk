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
    /// `-videoPath /path/clip.mp4` runs Vision on a video file instead of the camera or demo shooter.
    static var videoURL: URL? {
        UserDefaults.standard.string(forKey: "videoPath").map { URL(fileURLWithPath: $0) }
    }
    /// Shows a record of every spoken cue on screen (simulator, UI tests, or `-showSpokenCues`).
    static var showSpokenCues: Bool { isUITesting || isSimulator || arguments.contains("-showSpokenCues") }
    /// Benchmark: replay this keypoint file in a live session instead of showing the home screen.
    static var replayKeypointsPath: String? { value(after: "-replay-keypoints") }
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
    static let hasSeenSetupTips = "hasSeenSetupTips"
}
