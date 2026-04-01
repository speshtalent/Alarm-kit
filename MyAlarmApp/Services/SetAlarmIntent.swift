import Foundation
import AppIntents

// MARK: - Set Alarm Intent
struct SetAlarmIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Alarm"
    static var description = IntentDescription("Creates an alarm for a specific date and time.")

    // ✅ Combined date+time into one parameter — works in one sentence
    @Parameter(title: "When", description: "The date and time for the alarm")
    var when: Date

    @Parameter(title: "Label", description: "What the alarm is for", default: "Alarm")
    var label: String

    static var parameterSummary: some ParameterSummary {
        Summary("Set an alarm for \(\.$when) about \(\.$label)")
    }

    init() {}

    init(when: Date, label: String) {
        self.when = when
        self.label = label
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cleanedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = cleanedLabel.isEmpty ? "Alarm" : cleanedLabel

        // ✅ Validate not in past
        guard when > Date() else {
            return .result(dialog: IntentDialog("That time has already passed. Please set a future date and time."))
        }

        await AlarmService.shared.requestAuthorizationIfNeeded()
        _ = await AlarmService.shared.scheduleFutureAlarm(date: when, title: finalLabel)
        AlarmService.shared.loadAlarms()

        let formatted = when.formatted(
            Date.FormatStyle()
                .weekday(.wide)
                .month(.wide)
                .day(.defaultDigits)
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute(.twoDigits)
        )
        return .result(dialog: IntentDialog("Got it! '\(finalLabel)' alarm set for \(formatted)."))
    }
}

// MARK: - 5 Min Timer Intent
struct FiveMinTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "5 Minute Timer"
    static var description = IntentDescription("Instantly starts a 5 minute timer.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await TimerService.shared.startTimer(duration: 300, title: "5 Min Timer", sound: "nokia.caf")
        return .result(dialog: IntentDialog("5 minute timer started!"))
    }
}

// MARK: - Start Timer Intent
struct StartTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Timer"
    static var description = IntentDescription("Starts a countdown timer for a custom duration.")

    @Parameter(title: "Duration (minutes)")
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$minutes) minute timer")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let duration = TimeInterval(minutes * 60)
        await TimerService.shared.startTimer(duration: duration, title: "\(minutes) Min Timer", sound: "nokia.caf")
        return .result(dialog: IntentDialog("Started a \(minutes) minute timer!"))
    }
}

// MARK: - Open App Intent
struct OpenFutureAlarmIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Future Alarm"
    static var description = IntentDescription("Opens the Future Alarm app.")
    static var openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: IntentDialog("Opening Future Alarm!"))
    }
}

// MARK: - App Shortcuts
struct AlarmAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {

        // ✅ Set Alarm — natural language phrases
        AppShortcut(
            intent: SetAlarmIntent(),
            phrases: [
                "Set an alarm with \(.applicationName)",
                "Set alarm in \(.applicationName)",
                "Create alarm with \(.applicationName)",
                "Create alarm in \(.applicationName)",
                "Set an alarm in \(.applicationName)",
                "Remind me with \(.applicationName)",
                "Wake me up with \(.applicationName)",
                "Wake me up using \(.applicationName)",
                "Set a future alarm with \(.applicationName)",
                "Set a future alarm in \(.applicationName)",
                "Add alarm in \(.applicationName)",
                "New alarm in \(.applicationName)",
                "Schedule alarm in \(.applicationName)",
                "Set reminder in \(.applicationName)"
            ],
            shortTitle: "Set Alarm",
            systemImageName: "alarm"
        )

        // ✅ 5 Min Timer
        AppShortcut(
            intent: FiveMinTimerIntent(),
            phrases: [
                "Start 5 minute timer with \(.applicationName)",
                "5 min timer with \(.applicationName)",
                "Quick timer with \(.applicationName)"
            ],
            shortTitle: "5 Min Timer",
            systemImageName: "clock"
        )

        // ✅ Start Timer
        AppShortcut(
            intent: StartTimerIntent(),
            phrases: [
                "Start a timer with \(.applicationName)",
                "Set a timer with \(.applicationName)",
                "Start countdown with \(.applicationName)"
            ],
            shortTitle: "Start Timer",
            systemImageName: "timer"
        )

        // ✅ Open App
        AppShortcut(
            intent: OpenFutureAlarmIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Launch \(.applicationName)"
            ],
            shortTitle: "Open App",
            systemImageName: "arrow.up.right.square"
        )
    }
}
