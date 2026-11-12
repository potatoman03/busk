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
    /// Benchmark: replay this keypoint file in a live session instead of showing the home screen.
    static var replayKeypointsPath: String? { value(after: "-replay-keypoints") }
    static var replayLabel: String? { value(after: "-replay-label") }

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
