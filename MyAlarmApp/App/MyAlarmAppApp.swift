import SwiftUI
import AppIntents

@main
struct MyAlarmAppApp: App {

    init() {
        Task {
            await AlarmService.shared.requestAuthorizationIfNeeded()
        }
        AlarmAppShortcutsProvider.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
