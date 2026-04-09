import Foundation
import AppIntents

enum AlarmRecurrence: String, Codable, CaseIterable, AppEnum {
    case none
    case daily
    case weekly
    case custom

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Recurrence"

    static var caseDisplayRepresentations: [AlarmRecurrence: DisplayRepresentation] = [
        .none: "Does Not Repeat",
        .daily: "Daily",
        .weekly: "Weekly",
        .custom: "Custom"
    ]

    var repeatDays: Set<Int> {
        switch self {
        case .none:
            return []
        case .daily:
            return Set(1...7)
        case .weekly:
            return [Calendar.current.component(.weekday, from: Date())]
        case .custom:
            return []
        }
    }
}

struct PendingSetAlarmIntentDraft: Codable, Equatable {
    let date: Date
    let label: String
    let shouldRecordVoice: Bool
    let recurrence: AlarmRecurrence?

    var repeatDays: Set<Int> {
        guard let recurrence else { return [] }
        switch recurrence {
        case .none:
            return []
        case .daily:
            return Set(1...7)
        case .weekly:
            return [Calendar.current.component(.weekday, from: date)]
        case .custom:
            return []
        }
    }
}

enum PendingSetAlarmIntentStore {
    private static let key = "pendingSetAlarmIntentDraft"

    static func save(_ draft: PendingSetAlarmIntentDraft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func consume() -> PendingSetAlarmIntentDraft? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        return try? JSONDecoder().decode(PendingSetAlarmIntentDraft.self, from: data)
    }
}

enum SetAlarmIntentError: LocalizedError {
    case missingDate
    case emptyLabel
    case pastDate
    case schedulingFailed

    var errorDescription: String? {
        switch self {
        case .missingDate:
            return "Choose a date and time for the alarm."
        case .emptyLabel:
            return "Add a label so Date Alarm can tell this apart from Apple Clock."
        case .pastDate:
            return "Choose a time in the future."
        case .schedulingFailed:
            return "Date Alarm couldn't save that alarm right now. Please try again."
        }
    }

    var dialog: IntentDialog {
        IntentDialog(stringLiteral: errorDescription ?? "Something went wrong.")
    }
}

struct OpenDateAlarmIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Date Alarm"
    static var description = IntentDescription("Opens Date Alarm to finish alarm setup.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct SetAlarmIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Date Alarm"
    static var description = IntentDescription("Creates a labeled date alarm in Date Alarm for a specific future date and time, with optional repeat and voice recording setup.")

    // Keep this background-capable so Siri can complete normal alarms silently.
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Date",
        description: "Which day the alarm should go off.",
        kind: .date,
        requestValueDialog: IntentDialog("Which date should I set it for?")
    )
    var date: DateComponents

    @Parameter(
        title: "Time",
        description: "What time the alarm should go off.",
        kind: .time,
        requestValueDialog: IntentDialog("What time?")
    )
    var time: DateComponents

    @Parameter(
        title: "Label",
        description: "What the alarm is for, like 'pay rent' or 'airport pickup'."
    )
    var label: String?

    @Parameter(
        title: "Record Voice",
        description: "Open the app after setup so you can record a custom voice reminder.",
        default: false
    )
    var shouldRecordVoice: Bool

    @Parameter(
        title: "Recurrence",
        description: "Choose whether the alarm repeats daily, weekly, or stays one-time."
    )
    var recurrence: AlarmRecurrence?

    static var parameterSummary: some ParameterSummary {
        Summary("Create a date alarm for \(\.$date) at \(\.$time)")
    }

    init() {}

    init(date: DateComponents, time: DateComponents, label: String? = nil, shouldRecordVoice: Bool = false, recurrence: AlarmRecurrence? = nil) {
        self.date = date
        self.time = time
        self.label = label
        self.shouldRecordVoice = shouldRecordVoice
        self.recurrence = recurrence
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let validatedDate = try validatedDateValue()
            let cleanedLabel = try await resolvedLabel()
            let normalizedRecurrence = recurrence == AlarmRecurrence.none ? nil : recurrence

            if needsForegroundContinuation(for: normalizedRecurrence) {
                PendingSetAlarmIntentStore.save(
                    PendingSetAlarmIntentDraft(
                        date: validatedDate,
                        label: cleanedLabel,
                        shouldRecordVoice: shouldRecordVoice,
                        recurrence: normalizedRecurrence
                    )
                )

                return .result(
                    opensIntent: OpenDateAlarmIntent(),
                    dialog: handoffDialog(for: validatedDate, label: cleanedLabel, recurrence: normalizedRecurrence)
                )
            }

            await AlarmService.shared.requestAuthorizationIfNeeded()

            let repeatDays = repeatDays(for: normalizedRecurrence, date: validatedDate)
            let alarmID = await AlarmService.shared.scheduleFutureAlarm(
                date: validatedDate,
                title: cleanedLabel,
                repeatDays: repeatDays
            )

            guard alarmID != nil else {
                return .result(dialog: SetAlarmIntentError.schedulingFailed.dialog)
            }

            AlarmService.shared.loadAlarms()
            return .result(dialog: confirmationDialog(for: validatedDate, label: cleanedLabel, recurrence: normalizedRecurrence))
        } catch let error as SetAlarmIntentError {
            return .result(dialog: error.dialog)
        } catch {
            return .result(dialog: SetAlarmIntentError.schedulingFailed.dialog)
        }
    }

    private func validatedDateValue(referenceDate: Date = Date()) throws -> Date {
        let mergedDate = mergedDateTime()

        guard let mergedDate else {
            throw SetAlarmIntentError.missingDate
        }

        guard mergedDate > referenceDate else {
            throw SetAlarmIntentError.pastDate
        }

        return mergedDate
    }

    private func mergedDateTime() -> Date? {
        var mergedComponents = date
        mergedComponents.hour = time.hour
        mergedComponents.minute = time.minute
        mergedComponents.second = 0
        return Calendar.current.date(from: mergedComponents)
    }

    private func cleanedLabel(from value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validatedLabel(_ candidate: String) throws -> String {
        let cleanedLabel = cleanedLabel(from: candidate)
        guard !cleanedLabel.isEmpty else {
            throw SetAlarmIntentError.emptyLabel
        }
        return cleanedLabel
    }

    private func resolvedLabel() async throws -> String {
        let existingLabel = cleanedLabel(from: label)
        if !existingLabel.isEmpty {
            return try validatedLabel(existingLabel)
        }

        let requestedLabel = try await $label.requestValue(
            IntentDialog("Do you want to give this alarm a name or label so that you can remember why you set it in the first place?")
        )
        return try validatedLabel(requestedLabel)
    }

    private func needsForegroundContinuation(for recurrence: AlarmRecurrence?) -> Bool {
        shouldRecordVoice || recurrence == .custom
    }

    private func repeatDays(for recurrence: AlarmRecurrence?, date: Date) -> Set<Int> {
        guard let recurrence else { return [] }

        switch recurrence {
        case .none:
            return []
        case .daily:
            return Set(1...7)
        case .weekly:
            return [Calendar.current.component(.weekday, from: date)]
        case .custom:
            return []
        }
    }

    private func confirmationDialog(for date: Date, label: String, recurrence: AlarmRecurrence?) -> IntentDialog {
        let recurrenceSuffix: String
        switch recurrence {
        case .daily:
            recurrenceSuffix = ", repeating daily"
        case .weekly:
            recurrenceSuffix = ", repeating weekly"
        default:
            recurrenceSuffix = ""
        }

        return IntentDialog("Date alarm set for \(date.intentAlarmDisplayString)\(recurrenceSuffix): \(label)")
    }

    private func handoffDialog(for date: Date, label: String, recurrence: AlarmRecurrence?) -> IntentDialog {
        if shouldRecordVoice {
            return IntentDialog("I prepared \(label) for \(date.intentAlarmDisplayString). Open Date Alarm to record your custom voice alarm.")
        }

        if recurrence == .custom {
            return IntentDialog("I prepared \(label) for \(date.intentAlarmDisplayString). Open Date Alarm to finish the custom repeat schedule.")
        }

        return confirmationDialog(for: date, label: label, recurrence: recurrence)
    }
}

struct SetVoiceAlarmIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Voice Date Alarm"
    static var description = IntentDescription("Creates a date alarm and opens Date Alarm so you can record a custom voice reminder.")

    @Parameter(
        title: "Date",
        description: "Which day the alarm should go off.",
        kind: .date,
        requestValueDialog: IntentDialog("Which date should I set it for?")
    )
    var date: DateComponents

    @Parameter(
        title: "Time",
        description: "What time the alarm should go off.",
        kind: .time,
        requestValueDialog: IntentDialog("What time?")
    )
    var time: DateComponents

    @Parameter(
        title: "Label",
        description: "What the alarm is for."
    )
    var label: String?

    @Parameter(
        title: "Recurrence",
        description: "Choose whether the alarm repeats daily, weekly, or stays one-time."
    )
    var recurrence: AlarmRecurrence?

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await SetAlarmIntent(
            date: date,
            time: time,
            label: label,
            shouldRecordVoice: true,
            recurrence: recurrence
        ).perform()
    }
}

// MARK: - Timer Intents
struct FiveMinTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "5 Minute Timer"
    static var description = IntentDescription("Instantly starts a 5 minute timer.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await TimerService.shared.startTimer(duration: 300, title: "5 Min Timer", sound: "nokia.caf")
        return .result(dialog: IntentDialog("5 minute timer started."))
    }
}

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
        return .result(dialog: IntentDialog("Started a \(minutes) minute timer."))
    }
}

// MARK: - App Shortcuts
struct AlarmAppShortcutsProvider: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .orange

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetAlarmIntent(),
            phrases: [
                "Set a \(.applicationName)",
                "Create a \(.applicationName)",
                "Schedule a \(.applicationName)",
                "Plan a \(.applicationName)"
            ],
            shortTitle: "Set Alarm",
            systemImageName: "alarm"
        )
        AppShortcut(
            intent: FiveMinTimerIntent(),
            phrases: [
                "Start a 5 minute \(.applicationName) timer",
                "Set a 5 min \(.applicationName) timer"
            ],
            shortTitle: "5 Min Timer",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: StartTimerIntent(),
            phrases: [
                "Start a \(.applicationName) timer",
                "Set a \(.applicationName) timer"
            ],
            shortTitle: "Start Timer",
            systemImageName: "timer.circle"
        )
        AppShortcut(
            intent: OpenDateAlarmIntent(),
            phrases: [
                "Open \(.applicationName)"
            ],
            shortTitle: "Open App",
            systemImageName: "arrow.up.forward.app"
        )
    }
}

private extension Date {
    var intentAlarmDisplayString: String {
        formatted(
            Date.FormatStyle()
                .weekday(.wide)
                .month(.abbreviated)
                .day(.defaultDigits)
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute(.twoDigits)
        )
    }
}
