import SwiftUI
import AppIntents
import UIKit
import StoreKit // ✅ ADDED — for review popup
 
@main
struct MyAlarmAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var quickActionMode: String? = nil
 
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
 
    private func setupQuickActions() {
        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(
                type: "newAlarm",
                localizedTitle: "New Alarm",
                localizedSubtitle: "Set a new alarm",
                icon: UIApplicationShortcutIcon(systemImageName: "alarm"),
                userInfo: nil
            ),
            UIApplicationShortcutItem(
                type: "newTimer",
                localizedTitle: "New Timer",
                localizedSubtitle: "Set a new timer",
                icon: UIApplicationShortcutIcon(systemImageName: "timer"),
                userInfo: nil
            ),
            UIApplicationShortcutItem(
                type: "fiveMinTimer",
                localizedTitle: "5 Min Timer",
                localizedSubtitle: "Start a 5 minute timer now",
                icon: UIApplicationShortcutIcon(systemImageName: "clock"),
                userInfo: nil
            ),
            UIApplicationShortcutItem(
                type: "settings",
                localizedTitle: "Settings",
                localizedSubtitle: "Open Settings",
                icon: UIApplicationShortcutIcon(systemImageName: "gearshape"),
                userInfo: nil
            ),
        ]
    }
 
    // ✅ ADDED — shows review popup if alarm fired since last app open
    private func requestReviewIfNeeded() {
        let alarmFired = UserDefaults.standard.bool(forKey: "alarmFiredSinceLastReview")
        guard alarmFired else { return }
 
        // ✅ ADDED — clear flag so won't show again until next alarm fires
        UserDefaults.standard.set(false, forKey: "alarmFiredSinceLastReview")
 
        // ✅ ADDED — 1.5s delay so app is fully visible before popup appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                AppStore.requestReview(in: scene)
                print("⭐ Review popup shown!")
            }
        }
    }
 
    var body: some Scene {
        WindowGroup {
            ContentView(quickActionMode: $quickActionMode)
                .onAppear {
                    setupQuickActions()
                    print("✅ App launched")
                }
                // killed app case
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
 
                        // ✅ ADDED — show review if alarm fired since last open
                        requestReviewIfNeeded()
                    }
                }
                // background app case
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
 
    // killed app — connect SceneDelegate here
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
        // ✅ connect SceneDelegate for background case
        config.delegateClass = SceneDelegate.self
        return config
    }
}
