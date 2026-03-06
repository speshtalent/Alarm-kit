import SwiftUI
import AppIntents

@main
struct MyAlarmAppApp: App {

    init() {
        Task {
            await AlarmService.shared.requestAuthorizationIfNeeded()
        }
        AlarmAppShortcutsProvider.updateAppShortcutParameters()
        setupAlarmStopListener()
    }

    private func setupAlarmStopListener() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AlarmDidStop"),
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AlarmHandler.shared.playVoiceIfNeeded()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    Task { @MainActor in
                        if UserDefaults.standard.bool(forKey: "pendingVoicePlay") {
                            UserDefaults.standard.set(false, forKey: "pendingVoicePlay")
                            AlarmHandler.shared.playVoiceIfNeeded()
                        }
                    }
                }
        }
    }
}
