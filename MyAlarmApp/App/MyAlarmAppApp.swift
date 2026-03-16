import SwiftUI
import AppIntents
import UIKit
import StoreKit

@main
struct MyAlarmAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var quickActionMode: String? = nil
    @State private var showFeedbackAlert = false
    @State private var showFeedbackBox = false
    @State private var feedbackText = ""

    init() {
        #if DEBUG
        // ✅ TESTING ONLY — only show review after first alarm has been set
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

    var body: some Scene {
        WindowGroup {
            ContentView(quickActionMode: $quickActionMode)
                .onAppear {
                    setupQuickActions()
                    print("✅ App launched")
                }

                // STEP 1 — Alert
                .alert("Enjoying Future Alarm? 🔔", isPresented: $showFeedbackAlert) {
                    Button("Yes, Rate Us ⭐") {
                        showFeedbackBox = true
                    }
                    Button("Not Now", role: .cancel) { }
                } message: {
                    Text("We'd love to hear your thoughts! Rate us and share feedback 😊")
                }

                // STEP 2 — Stars + Feedback box together
                .sheet(isPresented: $showFeedbackBox) {
                    FeedbackView(feedbackText: $feedbackText) {
                        showFeedbackBox = false
                        feedbackText = ""
                        print("📝 Feedback submitted!")
                    }
                    .presentationDetents([.height(480)])
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

// ✅ UPDATED — Stars + Feedback message in one sheet
// ✅ UPDATED — Stars + Feedback message in one sheet
struct FeedbackView: View {
    @Binding var feedbackText: String
    @State private var selectedStars = 0
    @State private var showThankYou = false
    let onSubmit: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.09).ignoresSafeArea()
            VStack(spacing: 20) {

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(white: 0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, 12)

                Text("Rate & Review 🔔")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("How was your experience with Future Alarm?")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .multilineTextAlignment(.center)

                // ✅ UPDATED — gold when selected, gray when not
                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= selectedStars ? "star.fill" : "star")
                            .font(.system(size: 40))
                            // ✅ gold selected, gray unselected
                            .foregroundStyle(star <= selectedStars ? Color(red: 1.0, green: 0.84, blue: 0.0) : Color.gray.opacity(0.5))
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedStars = star
                                }
                            }
                    }
                }
                .padding(.vertical, 4)

                // ✅ UPDATED — white box, black text, gray placeholder
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    if feedbackText.isEmpty {
                        Text("Write your feedback here... (optional)")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Color.gray.opacity(0.55))
                            .padding(14)
                    }
                    TextEditor(text: $feedbackText)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.black)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .padding(10)
                        .tint(.blue)
                }
                .frame(height: 100)
                .padding(.horizontal, 24)

                // ✅ UPDATED — blue submit button
                Button {
                    if selectedStars > 0 {
                        showThankYou = true
                    }
                } label: {
                    Text(selectedStars == 0 ? "Select a Star to Submit" : "Submit")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        // ✅ blue when stars selected, gray when not
                        .background(selectedStars > 0 ? Color.blue : Color.gray.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .disabled(selectedStars == 0)
                .padding(.horizontal, 24)
                .alert("Thank You! 🎉", isPresented: $showThankYou) {
                    Button("Close") {
                        onSubmit()
                    }
                } message: {
                    Text("We really appreciate your feedback! It helps us make Future Alarm even better for you 😊")
                }

                Button("Maybe Later") {
                    onSubmit()
                }
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.35))
                .padding(.bottom, 8)
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
