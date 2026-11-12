import SwiftData
import SwiftUI

@main
struct BuskApp: App {
    let container: ModelContainer
    @State private var voiceControl = VoiceControl()
    @AppStorage(SettingsKey.voiceCommands) private var voiceCommands = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let config = ModelConfiguration(isStoredInMemoryOnly: AppEnvironment.isUITesting || AppEnvironment.replayKeypointsPath != nil
                                        || AppEnvironment.videoURL != nil)
        do {
            container = try ModelContainer(for: SessionRecord.self, configurations: config)
        } catch {
            container = try! ModelContainer(for: SessionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        if AppEnvironment.isUITesting {
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
            UIView.setAnimationsEnabled(false)
        }
        if let days = AppEnvironment.seedPracticeDays {
            PracticeSeed.insert(days: days, into: container.mainContext)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let path = AppEnvironment.replayKeypointsPath {
                    ReplaySessionView(path: path, label: AppEnvironment.replayLabel)
                } else if let video = AppEnvironment.videoURL {
                    ReplaySessionView(video: video, label: AppEnvironment.replayLabel)
                } else {
                    HomeView()
                }
            }
            .environment(voiceControl)
            .task(id: voiceCommands) {
                if voiceCommands { await voiceControl.start() } else { voiceControl.stop() }
            }
            .onChange(of: scenePhase) { _, phase in
                // Access may have just been granted in iOS Settings.
                if phase == .active && voiceCommands && voiceControl.state == .needsPermission {
                    Task { await voiceControl.start() }
                }
            }
            .tint(Theme.orange)
            .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
