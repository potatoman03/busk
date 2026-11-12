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
}

enum SettingsKey {
    static let voiceEnabled = "voiceEnabled"
    static let handedness = "handedness"
    static let cameraView = "cameraView"
    static let hasSeenSetupTips = "hasSeenSetupTips"
}
