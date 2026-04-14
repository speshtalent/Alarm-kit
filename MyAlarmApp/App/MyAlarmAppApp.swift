import SwiftUI
import AppIntents
import UIKit
import StoreKit
import Intents

@main
struct MyAlarmAppApp: App {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var quickActionMode: String? = nil
    @State private var showFeedbackAlert = false
    @State private var showVoiceRestoredAlert = false
    @State private var showAlarmRestorePermissionAlert = false

    init() {
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
                // ✅ Increment alarm fired count
                let count = UserDefaults.standard.integer(forKey: "alarmFiredCount") + 1
                UserDefaults.standard.set(count, forKey: "alarmFiredCount")
                UserDefaults.standard.set(true, forKey: "alarmFiredSinceLastReview")
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
        let appGroup = UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")

        var firedCount = 0
        if let json = appGroup?.string(forKey: "AlarmHistory"),
           let data = json.data(using: .utf8),
           let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            firedCount = list.count
        }

        guard firedCount >= 2 else { return }

        let lastReviewDate = UserDefaults.standard.double(forKey: "lastReviewRequestDate")
        let daysSinceLastReview = (Date().timeIntervalSince1970 - lastReviewDate) / 86400
        guard daysSinceLastReview >= 30 || lastReviewDate == 0 else { return }

        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastReviewRequestDate")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showFeedbackAlert = true
        }
    }

    private static func requestSiriAuthorizationIfNeeded() {
        guard INPreferences.siriAuthorizationStatus() == .notDetermined else { return }

        INPreferences.requestSiriAuthorization { status in
            #if DEBUG
            let statusDescription: String
            switch status {
            case .authorized:
                statusDescription = "authorized"
            case .denied:
                statusDescription = "denied"
            case .restricted:
                statusDescription = "restricted"
            case .notDetermined:
                statusDescription = "notDetermined"
            @unknown default:
                statusDescription = "unknown"
            }
            print("Siri authorization status: \(statusDescription)")
            #endif
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
            let restored = await AlarmService.shared.restoreFromiCloudIfNeeded()
            if restored {
                AlarmService.shared.loadAlarms()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    showVoiceRestoredAlert = true
                }
            } else if AlarmService.shared.pendingCloudRestoreRequiresAuthorization() {
                showAlarmRestorePermissionAlert = true
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(quickActionMode: $quickActionMode)
                .onAppear {
                    setupQuickActions()
                    if hasSeenOnboarding {
                        restoreFromiCloudIfNeeded()
                    }
                    print("✅ App launched")
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OnboardingCompleted"))) { _ in
                    // ✅ No automatic restore — user controls it from Settings
                }

                .alert("Alarms Restored 🔔", isPresented: $showVoiceRestoredAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Your alarms have been restored from iCloud. Note: Voice recordings could not be restored as they are stored locally on your device.")
                }

                .alert("Allow Alarm Access", isPresented: $showAlarmRestorePermissionAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Your iCloud alarm backup was downloaded to this device, but alarms cannot be recreated until Alarm access is available.")
                }

                .alert("Enjoying Date Alarm? 🔔", isPresented: $showFeedbackAlert) {
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
                        // ✅ Restore handled manually from Settings
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
