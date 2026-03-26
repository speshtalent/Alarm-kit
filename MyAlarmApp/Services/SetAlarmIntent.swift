import Foundation
import AppIntents

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
        _ = await AlarmService.shared.scheduleFutureAlarm(
            date: fireDate,
            title: finalLabel
        )
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

struct AlarmAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
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
    }
}
