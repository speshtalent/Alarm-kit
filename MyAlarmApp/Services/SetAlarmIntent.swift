import Foundation
import AppIntents

struct SetAlarmIntent: AppIntent, ProvidesDialog {
    var value: Never?
    
    static var title: LocalizedStringResource = "Set Alarm"
    static var description = IntentDescription("Creates an AlarmKit alarm for a specific date and label.")

    @Parameter(title: "Date", kind: .date)
    var date: Date

    @Parameter(title: "Time", kind: .time)
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

        // Shared service is used by SwiftUI and this intent so behavior stays identical.
        await AlarmService.shared.requestAuthorizationIfNeeded()
        _ = try await AlarmService.shared.scheduleAlarm(date: fireDate, label: finalLabel)
        AlarmService.shared.loadAlarms()

        let formatted = fireDate.formatted(
            Date.FormatStyle()
                .weekday(.wide)
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute(.twoDigits)
        )

        return .result(dialog: IntentDialog("Your alarm titled '\(finalLabel)' is set for \(formatted)."))
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
                "Use \(.applicationName) to set an alarm"
            ],
            shortTitle: "Set Alarm",
            systemImageName: "alarm"
        )
    }
}
