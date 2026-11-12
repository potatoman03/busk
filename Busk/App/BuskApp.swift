import SwiftData
import SwiftUI

@main
struct BuskApp: App {
    let container: ModelContainer

    init() {
        let config = ModelConfiguration(isStoredInMemoryOnly: AppEnvironment.isUITesting)
        do {
            container = try ModelContainer(for: SessionRecord.self, configurations: config)
        } catch {
            container = try! ModelContainer(for: SessionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        if AppEnvironment.isUITesting {
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .tint(Theme.orange)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
