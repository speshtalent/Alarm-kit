import SwiftUI
import AppIntents
import UIKit
import StoreKit

@main
struct MyAlarmAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var quickActionMode: String? = nil
    @State private var showFeedbackAlert = false
    @State private var showVoiceRestoredAlert = false

    init() {
        #if DEBUG
        let hasEverSetAlarm = UserDefaults.standard.bool(forKey: "hasEverSetAlarm")
        if hasEverSetAlarm {
            UserDefaults.standard.set(true, forKey: "alarmFiredSinceLastReview")
        }
        #endif

        Task {
            await AlarmService.shared.requestAuthorizationIfNeeded()
        }
        AlarmAppShortcutsProvider.updateAppShortcutParameters()
        setupAlarmStopListener()
        // ✅ NEW — listen for iCloud changes from other devices
        setupiCloudListener()
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

    // ✅ NEW — iCloud real-time listener
    private func setupiCloudListener() {
        NSUbiquitousKeyValueStore.default.synchronize()
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { _ in
            Task { @MainActor in
                let restored = await AlarmService.shared.restoreFromiCloud()
                if restored {
                    AlarmService.shared.loadAlarms()
                }
            }
        }
    }

    private func setupQuickActions() {
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(type: "newAlarm", localizedTitle: "New Alarm",
                localizedSubtitle: "Set a new alarm",
                icon: UIApplicationShortcutIcon(systemImageName: "alarm"), userInfo: nil),
            UIApplicationShortcutItem(type: "newTimer", localizedTitle: "New Timer",
                localizedSubtitle: "Set a new timer",
                icon: UIApplicationShortcutIcon(systemImageName: "timer"), userInfo: nil),
            UIApplicationShortcutItem(type: "fiveMinTimer", localizedTitle: "5 Min Timer",
                localizedSubtitle: "Start a 5 minute timer now",
                icon: UIApplicationShortcutIcon(systemImageName: "clock"), userInfo: nil),
            UIApplicationShortcutItem(type: "settings", localizedTitle: "Settings",
                localizedSubtitle: "Open Settings",
                icon: UIApplicationShortcutIcon(systemImageName: "gearshape"), userInfo: nil),
        ]
    }

    private func requestReviewIfNeeded() {
        let alarmFired = UserDefaults.standard.bool(forKey: "alarmFiredSinceLastReview")
        guard alarmFired else { return }
        UserDefaults.standard.set(false, forKey: "alarmFiredSinceLastReview")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showFeedbackAlert = true
        }
    }

    private func showNativeReview() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                AppStore.requestReview(in: scene)
                print("⭐ Native Apple review popup shown!")
            }
        }
    }

    private func restoreFromiCloudIfNeeded() {
        Task { @MainActor in
            let restored = await AlarmService.shared.restoreFromiCloud()
            if restored {
                AlarmService.shared.loadAlarms()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    showVoiceRestoredAlert = true
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(quickActionMode: $quickActionMode)
                .onAppear {
                    setupQuickActions()
                    restoreFromiCloudIfNeeded()
                    print("✅ App launched")
                }

                .alert("Alarms Restored 🔔", isPresented: $showVoiceRestoredAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Your alarms have been restored from iCloud. Note: Voice recordings could not be restored as they are stored locally on your device.")
                }

                .alert("Enjoying Future Alarm? 🔔", isPresented: $showFeedbackAlert) {
                    Button("Yes, Rate Us ⭐") {
                        showNativeReview()
                    }
                    Button("Not Now", role: .cancel) { }
                } message: {
                    Text("We'd love to hear your thoughts! Rate us on the App Store 😊")
                }

                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    Task { @MainActor in
                        if UserDefaults.standard.bool(forKey: "pendingVoicePlay") {
                            UserDefaults.standard.set(false, forKey: "pendingVoicePlay")
                            AlarmHandler.shared.playVoiceIfNeeded()
                        }
                        if let action = UserDefaults.standard.string(forKey: "quickAction") {
                            print("✅ Found action: \(action)")
                            UserDefaults.standard.removeObject(forKey: "quickAction")
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            quickActionMode = action
                        }
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        requestReviewIfNeeded()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("QuickActionTriggered"))) { notification in
                    if let action = notification.object as? String {
                        print("✅ QuickAction received: \(action)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            quickActionMode = action
                        }
                    }
                }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        print("✅ AppDelegate connected!")
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let shortcut = options.shortcutItem {
            print("🚀 Killed: \(shortcut.type)")
            UserDefaults.standard.set(shortcut.type, forKey: "quickAction")
            UserDefaults.standard.synchronize()
        }
        let config = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = SceneDelegate.self
        return config
    }
}
