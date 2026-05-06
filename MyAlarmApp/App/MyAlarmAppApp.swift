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
        setupTimeFormat()
        // Clear any zombie / leftover Live Activities (AlarmKit can keep them alive across reinstall).
        // Doing this here means a fresh install never starts with a phantom Dynamic Island pill.
        Task.detached(priority: .userInitiated) {
            await LiveActivityCoordinator.endAllActivities()
        }
    }

    private func setupTimeFormat() {
        // ✅ Only set on first launch
        guard !UserDefaults.standard.bool(forKey: "timeFormatInitialized") else { return }
        let is24Hour = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current)?.contains("a") == false
        UserDefaults.standard.set(is24Hour, forKey: "use24HourFormat")
        UserDefaults.standard.set(true, forKey: "timeFormatInitialized")
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
            UIApplicationShortcutItem(type: "settings", localizedTitle: "Settings",
                localizedSubtitle: "Open Settings",
                icon: UIApplicationShortcutIcon(systemImageName: "gearshape"), userInfo: nil),
            UIApplicationShortcutItem(type: "shareApp", localizedTitle: "Share App",
                localizedSubtitle: "Share Date Alarm with friends",
                icon: UIApplicationShortcutIcon(systemImageName: "square.and.arrow.up"), userInfo: nil),
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
                            print("✅ App launched")
                        }
                        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OnboardingCompleted"))) { _ in
                            // Request alarm authorization right after onboarding so we can query AlarmKit
                            // and cancel zombie alarms left over from prior installs (which otherwise
                            // render an empty Live Activity in the Dynamic Island after minimize).
                            Task { @MainActor in
                                await AlarmService.shared.requestAuthorizationIfNeeded()
                                AlarmService.shared.loadAlarms()
                            }
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
                        let appGroup = UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")
                        if let stoppedID = appGroup?.string(forKey: "pendingTimerStop"),
                           let uuid = UUID(uuidString: stoppedID) {
                            appGroup?.removeObject(forKey: "pendingTimerStop")
                            appGroup?.synchronize()
                            TimerService.shared.cancelTimer(id: uuid)
                            TimerService.shared.loadTimers()
                        }
                        AlarmService.shared.loadAlarms()
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
