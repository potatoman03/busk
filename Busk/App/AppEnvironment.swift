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
    /// `-videoPath /path/clip.mp4` runs Vision on a video file instead of the camera or demo shooter.
    static var videoURL: URL? {
        UserDefaults.standard.string(forKey: "videoPath").map { URL(fileURLWithPath: $0) }
    }
    /// Shows a record of every spoken cue on screen (simulator, UI tests, or `-showSpokenCues`).
    static var showSpokenCues: Bool { isUITesting || isSimulator || arguments.contains("-showSpokenCues") }
}

enum SettingsKey {
    static let voiceEnabled = "voiceEnabled"
    static let handedness = "handedness"
    static let cameraView = "cameraView"
    static let hasSeenSetupTips = "hasSeenSetupTips"
}
