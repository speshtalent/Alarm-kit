import SwiftUI
import AppIntents
import CoreData

@main
struct MyAlarmAppApp: App {
    private let persistenceController = PersistenceController.shared

    init() {
        Task {
            await AlarmService.shared.requestAuthorizationIfNeeded()
            _ = await AudioManager.shared.requestMicrophonePermission()
        }

        AlarmPlaybackCoordinator.shared.start()
        AlarmAppShortcutsProvider.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
