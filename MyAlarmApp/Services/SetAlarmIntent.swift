import Foundation
import AppIntents

// MARK: - Set Alarm Intent (existing — unchanged)
struct SetAlarmIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Alarm"
    static var description = IntentDescription("Creates an alarm for a specific date and time.")

    @Parameter(title: "Date")
    var date: Date

    @Parameter(title: "Time")
    var time: Date

    @Parameter(title: "Label")
    var label: String

    static var parameterSummary: some ParameterSummary {
        Summary("Set an alarm for \(\.$date) at \(\.$time) about \(\.$label)")
    }

    init() {}

    init(date: Date, time: Date, label: String) {
        self.date = date
        self.time = time
        self.label = label
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cleanedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = cleanedLabel.isEmpty ? "Alarm" : cleanedLabel
        let fireDate = Self.combineDateAndTime(date: date, time: time)
        await AlarmService.shared.requestAuthorizationIfNeeded()
        _ = await AlarmService.shared.scheduleFutureAlarm(date: fireDate, title: finalLabel)
        AlarmService.shared.loadAlarms()
        let formatted = fireDate.formatted(
            Date.FormatStyle()
                .weekday(.wide)
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute(.twoDigits)
        )
        return .result(dialog: IntentDialog("Got it! '\(finalLabel)' alarm set for \(formatted)."))
    }

    private static func combineDateAndTime(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        var merged = DateComponents()
        merged.year = dateComponents.year
        merged.month = dateComponents.month
        merged.day = dateComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute
        merged.second = 0
        return calendar.date(from: merged) ?? date
    }
}

// MARK: - ✅ NEW — 5 Min Timer Intent
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

// MARK: - ✅ NEW — Start Timer Intent
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

// MARK: - ✅ NEW — Open App Intent
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

        // ✅ Set Alarm
        AppShortcut(
            intent: SetAlarmIntent(),
            phrases: [
                "Set an alarm with \(.applicationName)",
                "Create alarm with \(.applicationName)",
                "Use \(.applicationName) to set an alarm",
                "Remind me with \(.applicationName)",
                "Wake me up with \(.applicationName)"
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
