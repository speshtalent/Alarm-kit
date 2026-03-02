import Foundation
import AppIntents

struct SetAlarmIntent: AppIntent, ProvidesDialog {
    var value: Never?
    
    static var title: LocalizedStringResource = "Set Alarm"
    static var description = IntentDescription("Creates an AlarmKit alarm for a specific date and label.")

    @Parameter(title: "Date")
    var date: Date

    @Parameter(title: "Label")
    var label: String

    static var parameterSummary: some ParameterSummary {
        Summary("Set an alarm for \(\.$date) about \(\.$label)")
    }

    init() {}

    init(date: Date, label: String) {
        self.date = date
        self.label = label
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cleanedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = cleanedLabel.isEmpty ? "Alarm" : cleanedLabel

        // Shared service is used by SwiftUI and this intent so behavior stays identical.
        await AlarmService.shared.requestAuthorizationIfNeeded()
        _ = try await AlarmService.shared.scheduleAlarm(date: date, label: finalLabel)
        AlarmService.shared.loadAlarms()

        let formatted = date.formatted(
            Date.FormatStyle()
                .weekday(.wide)
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute(.twoDigits)
        )

        return .result(dialog: IntentDialog("Your alarm titled '\(finalLabel)' is set for \(formatted)."))
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
