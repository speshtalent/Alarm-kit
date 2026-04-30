import Foundation
import Combine
import AlarmKit
import ActivityKit
import SwiftUI
import AppIntents
import WidgetKit

@MainActor
final class AlarmService: ObservableObject {

    struct CloudAlarm: Codable {
        let id: String
        let label: String
        let fireDate: TimeInterval
        let repeatDays: [Int]
        let isEnabled: Bool
        let sound: String?
        let calendarEnabled: Bool?
    }

    struct AlarmListItem: Identifiable, Hashable {
        let alarm: Alarm?
        let storedID: UUID
        let label: String
        var isEnabled: Bool
        let storedFireDate: Date?

        init(alarm: Alarm, label: String, isEnabled: Bool, storedFireDate: Date? = nil) {
            self.alarm = alarm
            self.storedID = alarm.id
            self.label = label
            self.isEnabled = isEnabled
            self.storedFireDate = storedFireDate
        }

        init(id: UUID, label: String, isEnabled: Bool, fireDate: Date?) {
            self.alarm = nil
            self.storedID = id
            self.label = label
            self.isEnabled = isEnabled
            self.storedFireDate = fireDate
        }

        var id: UUID { alarm?.id ?? storedID }
        var fireDate: Date? {
            guard let alarm else { return storedFireDate }
            guard let schedule = alarm.schedule else { return storedFireDate }
            guard case let .fixed(date) = schedule else { return nil }
            return date
        }

        static func == (lhs: AlarmListItem, rhs: AlarmListItem) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    struct AlarmGroup: Identifiable, Hashable {
        let id: UUID
        let label: String
        var isEnabled: Bool
        let alarmIDs: [UUID]
        let fireDate: Date?
        let repeatDays: Set<Int>
        var isFired: Bool = false  // ✅ new

        var repeatLabel: String {
            if repeatDays.isEmpty { return "" }
            // ✅ Monthly and Yearly
            if repeatDays == Set([100]) { return "Monthly" }
            if repeatDays == Set([200]) { return "Yearly" }
            // ✅ Monthly with selected months (101-112)
            let monthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
            let selectedMonths = repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted()
            if !selectedMonths.isEmpty { return selectedMonths.map { monthNames[$0 - 101] }.joined(separator: ", ") }
            // ✅ Yearly with selected years (2025+)
            let selectedYears = repeatDays.filter { $0 >= 2025 }.sorted()
            if !selectedYears.isEmpty { return selectedYears.map { "\($0)" }.joined(separator: ", ") }
            let weekDays: [(label: String, value: Int)] = [
                ("Mon", 2), ("Tue", 3), ("Wed", 4),
                ("Thu", 5), ("Fri", 6), ("Sat", 7), ("Sun", 1)
            ]
            let isActuallyWeekly = !repeatDays.contains { $0 >= 8 } && !repeatDays.contains { $0 >= 100 }
            guard isActuallyWeekly else { return "" }
            if repeatDays.count == 7 { return "Every day" }
            if repeatDays == Set([2, 3, 4, 5, 6]) { return "Weekdays" }
            if repeatDays == Set([7, 1]) { return "Weekends" }
            return weekDays.filter { repeatDays.contains($0.value) }.map { $0.label }.joined(separator: ", ")

        }

        static func == (lhs: AlarmGroup, rhs: AlarmGroup) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    static let shared = AlarmService()

    @Published var alarms: [AlarmListItem] = []
    @Published var alarmGroups: [AlarmGroup] = []

    private let labelsStoreKey     = "AlarmLabelsByID"
    private let disabledAlarmsKey  = "DisabledAlarmIDs"
    private let groupIDsKey        = "AlarmGroupIDs"
    private let alarmToGroupKey    = "AlarmToGroupID"
    private let groupRepeatDaysKey = "GroupRepeatDays"
    private let groupCalendarEnabledKey = "GroupCalendarEnabled"
    private let iCloudAlarmsKey    = "iCloudAlarmBackup"
    private let hasLaunchedBeforeKey = "hasLaunchedBefore"
    private let pendingCloudRestoreKey = "PendingCloudAlarmRestore"

    private var backupWorkItem: DispatchWorkItem?

    private init() {}

    private func snoozeDuration(for id: UUID) -> TimeInterval {
        let appGroup = UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")
        let globalMinutes = appGroup?.double(forKey: "globalSnoozeDuration") ?? UserDefaults.standard.double(forKey: "globalSnoozeDuration")
        if globalMinutes > 0 { return globalMinutes * 60 }

        let storedSeconds = appGroup?.double(forKey: "snoozeDuration_\(id.uuidString)") ?? UserDefaults.standard.double(forKey: "snoozeDuration_\(id.uuidString)")
        return storedSeconds > 0 ? storedSeconds : 5 * 60
    }

    private func makeAlarmPresentation(title: String) -> AlarmPresentation {
        let titleResource = LocalizedStringResource(stringLiteral: title)
        let countdown = AlarmPresentation.Countdown(
            title: LocalizedStringResource(stringLiteral: "Snoozed")
        )

        if #available(iOS 26.1, *) {
            let alert = AlarmPresentation.Alert(
                title: titleResource,
                stopButton: AlarmButton(
                    text: "Stop Alarm",
                    textColor: .white,
                    systemImageName: "alarm.fill"
                ),
                secondaryButton: AlarmButton(
                    text: "Snooze",
                    textColor: .white,
                    systemImageName: "moon.zzz.fill"
                ),
                secondaryButtonBehavior: .countdown
            )
            // WHY: AlarmKit owns the Lock Screen snooze transition; providing countdown
            // presentation lets the existing alarm activity become the snoozed countdown.
            return AlarmPresentation(alert: alert, countdown: countdown)
        } else {
            let alert = AlarmPresentation.Alert(
                title: titleResource,
                stopButton: AlarmButton(
                    text: "Stop Alarm",
                    textColor: .white,
                    systemImageName: "alarm.fill"
                )
            )
            return AlarmPresentation(alert: alert, countdown: countdown)
        }
    }

    func requestAuthorizationIfNeeded() async {
        do {
            if AlarmManager.shared.authorizationState == .authorized { return }
            _ = try await AlarmManager.shared.requestAuthorization()
        } catch {
            print("Alarm authorization error:", error)
        }
    }

    @discardableResult
    func scheduleAlarm(date: Date, label: String, sound: String = "nokia.caf") async throws -> UUID {
        let scheduleDate = max(date, Date().addingTimeInterval(1))
        let id = Alarm.ID()
        await LiveActivityCoordinator.endAlarmActivities()
        let presentation = makeAlarmPresentation(title: label)
        let attributes: AlarmAttributes<AlarmLiveActivityMetadata> = AlarmAttributes(
            presentation: presentation,
            metadata: AlarmLiveActivityMetadata(title: label, icon: "alarm.fill"),
            tintColor: .orange
        )
        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: snoozeDuration(for: id)),
            schedule: .fixed(scheduleDate),
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: id.uuidString),
            secondaryIntent: nil,
            sound: .named(sound)
        )
        let alarm = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        saveStoredFireDate(scheduleDate, for: id)
        saveLabel(label, for: id)
        upsertAlarmInList(alarm, label: label)
        NotificationService.shared.scheduleNotifications(for: id, label: label, fireDate: scheduleDate)
        return id
    }

    func cancelAlarm(id: UUID) {
        let groupID = getGroupID(for: id) ?? id
        let groupAlarmIDs = getAlarmIDs(forGroup: groupID)
        let idsToCancel = groupAlarmIDs.isEmpty ? [id] : groupAlarmIDs
        let shouldSyncCalendar = isCalendarEnabled(forGroup: groupID)

        for alarmID in idsToCancel {
            if shouldSyncCalendar {
                if let item = alarms.first(where: { $0.id == alarmID }), let fireDate = item.fireDate {
                    let key = fireDate.timeIntervalSince1970.description
                    CalendarService.shared.removeAlarmFromCalendar(alarmID: key)
                } else if let savedInterval = UserDefaults.standard.object(forKey: "disabledAlarmDate_\(alarmID.uuidString)") as? TimeInterval {
                    let key = savedInterval.description
                    CalendarService.shared.removeAlarmFromCalendar(alarmID: key)
                }
            }
            deleteVoiceFile(for: alarmID.uuidString)
            do {
                try AlarmManager.shared.cancel(id: alarmID)
            } catch {
                print("Cancel alarm error:", error)
            }
            NotificationService.shared.cancelNotifications(for: alarmID)
            removeLabel(for: alarmID)
            removeFromDisabled(id: alarmID)
            removeStoredFireDate(for: alarmID)
            alarms.removeAll { $0.id == alarmID }
        }

        removeFiredAlarm(alarmID: groupID.uuidString)
        removeGroup(groupID: groupID)
        rebuildGroups()
        saveNextAlarmForWidget()
        backupToiCloudDebounced()
    }

    func toggleAlarm(id: UUID) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        let item = alarms[index]

        if item.isEnabled {
            do {
                // ✅ Save fireDate before cancelling
                if let fireDate = item.fireDate {
                    UserDefaults.standard.set(fireDate.timeIntervalSince1970, forKey: "disabledAlarmDate_\(id.uuidString)")
                }
                do {
                    try AlarmManager.shared.cancel(id: id)
                } catch {
                    print("Cancel alarm error:", error)
                }
                alarms[index] = AlarmListItem(id: item.id, label: item.label, isEnabled: false, fireDate: item.fireDate)
                saveDisabledState(id: id, disabled: true)
                let groupID = getGroupID(for: id) ?? id
                if isCalendarEnabled(forGroup: groupID) {
                    let groupAlarmIDs = getAlarmIDs(forGroup: groupID)
                    let idsToRemove = groupAlarmIDs.isEmpty ? [id] : groupAlarmIDs
                    for alarmID in idsToRemove {
                        if let alarmFireDate = alarms.first(where: { $0.id == alarmID })?.fireDate {
                            let key = alarmFireDate.timeIntervalSince1970.description
                            CalendarService.shared.removeAlarmFromCalendar(alarmID: key)
                        }
                    }
                }
                print("⏸ Alarm disabled: \(id)")
            }
            saveNextAlarmForWidget()
            backupToiCloudDebounced()
        } else {
            // ✅ Try to get fireDate from saved UserDefaults if nil
            let storedFireDate: Date
            print("🔍 item.fireDate: \(String(describing: item.fireDate))")
            print("🔍 savedInterval: \(String(describing: UserDefaults.standard.object(forKey: "disabledAlarmDate_\(id.uuidString)")))")
            if let fd = item.fireDate {
                storedFireDate = fd
            } else if let savedInterval = UserDefaults.standard.object(forKey: "disabledAlarmDate_\(id.uuidString)") as? TimeInterval {
                storedFireDate = Date(timeIntervalSince1970: savedInterval)
            } else {
                print("⚠️ No fire date found")
                return
            }

            let groupID = getGroupID(for: id) ?? id
            let repeatDays = getRepeatDays(forGroup: groupID)
            let fireDate = repeatDays.isEmpty ? nextEnabledOneTimeDate(from: storedFireDate) : storedFireDate
            Task {
                do {
                    await requestAuthorizationIfNeeded()
                    let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                    let voiceFileName = "alarm_voice_\(id.uuidString).caf"
                    let voicePath = libraryURL.appendingPathComponent("Sounds/\(voiceFileName)").path
                    let sound = FileManager.default.fileExists(atPath: voicePath) ? voiceFileName : "nokia.caf"
                    try await scheduleAlarmWithID(id: id, date: fireDate, label: item.label, sound: sound)
                    saveDisabledState(id: id, disabled: false)
                    await syncCalendarIfNeeded(groupID: groupID, title: item.label, repeatDays: repeatDays)
                    print("▶️ Alarm re-enabled with sound: \(sound)")
                } catch {
                    print("Re-enable alarm error:", error)
                }
                saveNextAlarmForWidget()
                backupToiCloudDebounced()
            }
        }
    }

    func toggleGroup(groupID: UUID) {
        let groupAlarmIDs = getAlarmIDs(forGroup: groupID)
        for alarmID in groupAlarmIDs {
            toggleAlarm(id: alarmID)
        }
        rebuildGroups()
    }

    private struct LiveActivitySyncInputs {
        let removedOrphanTimers: Bool
        let labels: [String: String]
        let alarmKitSnapshot: Result<[Alarm], Error>
        let activeSnoozes: [String: Date]
        let hasTimers: Bool
        let persistedGroups: Bool
        let snoozeActive: Bool
    }

    /// Reloads alarms from AlarmKit / storage (synchronous), then schedules Live Activity sync.
    func loadAlarms() {
        let inputs = performLoadAlarmsSynchronously()
        Task {
            await synchronizeLiveActivities(inputs)
        }
    }

    /// Same as `loadAlarms()` but **awaits** Live Activity / Dynamic Island teardown before returning.
    /// Use when going to background so idle users don’t keep a phantom Island pill after suspend.
    func loadAlarmsAwaitingLiveActivitySync() async {
        let inputs = performLoadAlarmsSynchronously()
        await synchronizeLiveActivities(inputs)
    }

    private func performLoadAlarmsSynchronously() -> LiveActivitySyncInputs {
        let labels = loadLabels()
        let removedOrphanTimers = TimerService.shared.cancelOrphanAlarmKitTimerRecords()
        let alarmKitSnapshot: Result<[Alarm], Error>
        do {
            let all = try AlarmManager.shared.alarms
            alarmKitSnapshot = .success(all)
            let disabled = loadDisabledIDs()
            let groupIDs = loadGroupIDs()
            let repeatDaysDict = loadGroupRepeatDays()

            // ✅ Active alarms from AlarmKit
            var loadedAlarms = all
                .filter { $0.schedule != nil || UserDefaults.standard.bool(forKey: "isSnoozed_\($0.id.uuidString)") }
                .map { alarm in
                    let isSnoozed = UserDefaults.standard.bool(forKey: "isSnoozed_\(alarm.id.uuidString)")
                    let snoozeDate: Date? = isSnoozed ? {
                        guard let interval = UserDefaults.standard.object(forKey: "disabledAlarmDate_\(alarm.id.uuidString)") as? TimeInterval else { return nil }
                        return Date(timeIntervalSince1970: interval)
                    }() : nil
                    return AlarmListItem(
                        alarm: alarm,
                        label: labels[alarm.id.uuidString] ?? "Alarm",
                        isEnabled: !disabled.contains(alarm.id.uuidString) || isSnoozed,
                        storedFireDate: snoozeDate
                    )
                }

            // ✅ Add disabled alarms that are not in AlarmKit anymore
            let activeIDs = Set(loadedAlarms.map { $0.id.uuidString })
            var localOnlyIDs = disabled
            for (groupID, alarmIDs) in groupIDs {
                let repeatDays = repeatDaysDict[groupID] ?? []
                guard repeatDays.isEmpty, alarmIDs.count == 1, let alarmID = alarmIDs.first else { continue }
                localOnlyIDs.insert(alarmID)
            }

            for localID in localOnlyIDs {
                if !activeIDs.contains(localID),
                   let savedInterval = UserDefaults.standard.object(forKey: "disabledAlarmDate_\(localID)") as? TimeInterval,
                   let uuid = UUID(uuidString: localID) {
                    let fireDate = Date(timeIntervalSince1970: savedInterval)
                    let groupID = getGroupID(for: uuid) ?? uuid
                    let label = labels[localID] ?? labels[groupID.uuidString] ?? "Alarm"

                    if !disabled.contains(localID) {
                        saveDisabledState(id: uuid, disabled: true)
                    }

                    loadedAlarms.append(AlarmListItem(id: uuid, label: label, isEnabled: false, fireDate: fireDate))
                }
            }

            alarms = loadedAlarms.sorted { lhs, rhs in
                (lhs.fireDate ?? .distantFuture) < (rhs.fireDate ?? .distantFuture)
            }
        } catch {
            print("Load alarms error:", error)
            alarmKitSnapshot = .failure(error)
            alarms = []
        }
        rebuildGroups()
        saveNextAlarmForWidget()
        rescheduleIfFired()

        let activeSnoozes: [String: Date] = Dictionary(
            uniqueKeysWithValues: alarms.compactMap { item -> (String, Date)? in
                guard UserDefaults.standard.bool(forKey: "isSnoozed_\(item.id.uuidString)"),
                      let fireDate = item.fireDate,
                      fireDate > Date() else { return nil }
                return (item.id.uuidString, fireDate)
            }
        )
        let hasTimers = TimerService.shared.hasActiveStoredTimers()
        let persistedGroups = !loadGroupIDs().isEmpty
        let snoozeActive = !activeSnoozes.isEmpty

        return LiveActivitySyncInputs(
            removedOrphanTimers: removedOrphanTimers,
            labels: labels,
            alarmKitSnapshot: alarmKitSnapshot,
            activeSnoozes: activeSnoozes,
            hasTimers: hasTimers,
            persistedGroups: persistedGroups,
            snoozeActive: snoozeActive
        )
    }

    private func synchronizeLiveActivities(_ inputs: LiveActivitySyncInputs) async {
        if inputs.removedOrphanTimers {
            await LiveActivityCoordinator.endTimerActivities()
        }
        await LiveActivityCoordinator.syncSnoozeActivities(
            activeSnoozes: inputs.activeSnoozes,
            labels: inputs.labels
        )
        await LiveActivityCoordinator.reconcileIdleIslandPresentation(
            alarmKitSnapshot: inputs.alarmKitSnapshot,
            hasActiveSnooze: inputs.snoozeActive,
            hasActiveLocalTimers: inputs.hasTimers,
            userHasPersistedAlarmGroups: inputs.persistedGroups
        )
    }

    func rebuildGroups() {
        let groupIDsDict = loadGroupIDs()
        let repeatDaysDict = loadGroupRepeatDays()
        let labels = loadLabels()

        var groups: [AlarmGroup] = []

        for (groupIDStr, alarmIDStrs) in groupIDsDict {
            guard let groupID = UUID(uuidString: groupIDStr) else { continue }
            let alarmIDs = alarmIDStrs.compactMap { UUID(uuidString: $0) }
            let repeatDays = Set(repeatDaysDict[groupIDStr] ?? [])
            let groupAlarms = alarms.filter { alarmIDs.contains($0.id) }
            guard !groupAlarms.isEmpty else { continue }

            let earliest = groupAlarms.compactMap { $0.fireDate }.min()
            let label = labels[groupIDStr] ?? groupAlarms.first?.label ?? "Alarm"
            let isEnabled = groupAlarms.contains { $0.isEnabled }

            groups.append(AlarmGroup(
                id: groupID,
                label: label,
                isEnabled: isEnabled,
                alarmIDs: alarmIDs,
                fireDate: earliest,
                repeatDays: repeatDays
            ))
        }

        let groupedAlarmIDs = Set(groupIDsDict.values.flatMap { $0 }.compactMap { UUID(uuidString: $0) })
        for alarm in alarms where !groupedAlarmIDs.contains(alarm.id) {
            groups.append(AlarmGroup(
                id: alarm.id,
                label: alarm.label,
                isEnabled: alarm.isEnabled,
                alarmIDs: [alarm.id],
                fireDate: alarm.fireDate,
                repeatDays: []
            ))
        }

        alarmGroups = groups.sorted { lhs, rhs in
            (lhs.fireDate ?? .distantFuture) < (rhs.fireDate ?? .distantFuture)
        }
    }

    func scheduleFutureAlarm(
        date: Date,
        title: String,
        snoozeEnabled: Bool = true,
        snoozeDuration: TimeInterval = 300,
        sound: String = "nokia.caf",
        repeatDays: Set<Int> = [],
        calendarEnabled: Bool = false
    ) async -> UUID? {
        do {
            let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            let tempURL = libraryURL.appendingPathComponent("Sounds/alarm_voice_temp.caf")
            let tempExists = FileManager.default.fileExists(atPath: tempURL.path)
            let customSoundURL = sound.hasPrefix("custom_voice_") ? libraryURL.appendingPathComponent("Sounds/\(sound)") : nil
            let customSoundExists = customSoundURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            let sourceURL = customSoundExists ? customSoundURL! : tempURL
            let sourceExists = customSoundExists || tempExists

            let alarmID = UUID()
            var finalSound = sound
            let appGroup = UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")

            let isMonthly = repeatDays == Set([100]) || repeatDays.allSatisfy { $0 >= 101 && $0 <= 112 }
            let isYearly = repeatDays == Set([200]) || repeatDays.allSatisfy { $0 >= 2025 }
            if sourceExists && (repeatDays.isEmpty || isMonthly || isYearly) {
                let voiceFileName = "alarm_voice_\(alarmID.uuidString).caf"
                let destURL = libraryURL.appendingPathComponent("Sounds/\(voiceFileName)")
                try? FileManager.default.removeItem(at: destURL)
                try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                finalSound = voiceFileName
                print("✅ Voice file saved as: \(voiceFileName)")
            }
            UserDefaults.standard.set(snoozeDuration, forKey: "snoozeDuration_\(alarmID.uuidString)")
            appGroup?.set(snoozeDuration, forKey: "snoozeDuration_\(alarmID.uuidString)")

            // ✅ Monthly — schedule single alarm, save with repeatDays Set([100])
            if repeatDays == Set([100]) {
                let id = try await scheduleAlarmWithID(id: alarmID, date: date, label: title, sound: finalSound)
                saveGroup(groupID: id, alarmIDs: [id], label: title, repeatDays: Set([100]), calendarEnabled: calendarEnabled)
                UserDefaults.standard.set(sound, forKey: "alarmSound_\(id.uuidString)")
                await syncCalendarIfNeeded(groupID: id, title: title, repeatDays: Set([100]))
                rebuildGroups()
                saveNextAlarmForWidget()
                backupToiCloudDebounced()
                return id
            }

            // ✅ Monthly with only day selected (no months, no years, no forever/once flags)
            let onlyDaySelected = !repeatDays.filter { $0 >= 8 && $0 <= 31 }.isEmpty &&
                                   repeatDays.filter { $0 >= 101 && $0 <= 112 }.isEmpty &&
                                   repeatDays.filter { $0 >= 2025 }.isEmpty &&
                                   !repeatDays.contains(100) &&
                                   !repeatDays.contains(200) &&
                                   repeatDays.filter { $0 >= 201 }.isEmpty
            if onlyDaySelected {
                let id = try await scheduleAlarmWithID(id: alarmID, date: date, label: title, sound: finalSound)
                saveGroup(groupID: id, alarmIDs: [id], label: title, repeatDays: repeatDays, calendarEnabled: calendarEnabled)
                UserDefaults.standard.set(sound, forKey: "alarmSound_\(id.uuidString)")
                await syncCalendarIfNeeded(groupID: id, title: title, repeatDays: repeatDays)
                rebuildGroups()
                saveNextAlarmForWidget()
                backupToiCloudDebounced()
                return id
            }

            // ✅ Yearly with only date+year selected (no month values 101-112)
            let hasYearNoMonth = !repeatDays.filter { $0 >= 2025 }.isEmpty &&
                                  repeatDays.filter { $0 >= 101 && $0 <= 112 }.isEmpty
            if hasYearNoMonth {
                let id = try await scheduleAlarmWithID(id: alarmID, date: date, label: title, sound: finalSound)
                saveGroup(groupID: id, alarmIDs: [id], label: title, repeatDays: repeatDays, calendarEnabled: calendarEnabled)
                UserDefaults.standard.set(sound, forKey: "alarmSound_\(id.uuidString)")
                await syncCalendarIfNeeded(groupID: id, title: title, repeatDays: repeatDays)
                rebuildGroups()
                saveNextAlarmForWidget()
                backupToiCloudDebounced()
                return id
            }

            // ✅ Monthly with selected months (101-112)
            let selectedMonths = repeatDays.filter { $0 >= 101 && $0 <= 112 }
            if !selectedMonths.isEmpty {
                let calendar = Calendar.current
                let timeComponents = calendar.dateComponents([.hour, .minute], from: date)
                let dayOfMonth = repeatDays.filter { $0 >= 1 && $0 <= 31 }.first ?? calendar.component(.day, from: date)
                let groupID = UUID()
                var scheduledIDs: [UUID] = []
                for month in selectedMonths.sorted() {
                    let monthNumber = month - 100
                    var components = DateComponents()
                    components.month = monthNumber
                    components.day = dayOfMonth
                    components.hour = timeComponents.hour
                    components.minute = timeComponents.minute
                    components.second = 0
                    var fullComponents = DateComponents()
                    fullComponents.year = calendar.component(.year, from: date)
                    fullComponents.month = monthNumber
                    fullComponents.day = dayOfMonth
                    fullComponents.hour = timeComponents.hour
                    fullComponents.minute = timeComponents.minute
                    fullComponents.second = 0
                    let candidateDate = calendar.date(from: fullComponents)
                    let nextDate: Date
                    if let cd = candidateDate, cd > Date() {
                        nextDate = cd
                    } else {
                        fullComponents.year = calendar.component(.year, from: date) + 1
                        nextDate = calendar.date(from: fullComponents) ?? date
                    }
                    let recurringID = UUID()
                    var recurringSound = sound
                    if sourceExists {
                        let voiceFileName = "alarm_voice_\(recurringID.uuidString).caf"
                        let destURL = libraryURL.appendingPathComponent("Sounds/\(voiceFileName)")
                        try? FileManager.default.removeItem(at: destURL)
                        try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                        recurringSound = voiceFileName
                    }
                    _ = try await scheduleAlarmWithID(id: recurringID, date: nextDate, label: title, sound: recurringSound)
                    scheduledIDs.append(recurringID)
                    print("✅ Monthly alarm set for month \(monthNumber) at \(nextDate)")
                }
                saveGroup(groupID: groupID, alarmIDs: scheduledIDs, label: title, repeatDays: repeatDays, calendarEnabled: calendarEnabled)
                UserDefaults.standard.set(sound, forKey: "alarmSound_\(groupID.uuidString)")
                await syncCalendarIfNeeded(groupID: groupID, title: title, repeatDays: repeatDays)
                rebuildGroups()
                saveNextAlarmForWidget()
                backupToiCloudDebounced()
                return scheduledIDs.first
            }

            // ✅ Yearly — schedule single alarm, save with repeatDays Set([200])
            if repeatDays == Set([200]) {
                let id = try await scheduleAlarmWithID(id: alarmID, date: date, label: title, sound: finalSound)
                saveGroup(groupID: id, alarmIDs: [id], label: title, repeatDays: Set([200]), calendarEnabled: calendarEnabled)
                UserDefaults.standard.set(sound, forKey: "alarmSound_\(id.uuidString)")
                await syncCalendarIfNeeded(groupID: id, title: title, repeatDays: Set([200]))
                rebuildGroups()
                saveNextAlarmForWidget()
                backupToiCloudDebounced()
                return id
            }

            // ✅ Yearly with selected years (2025+)
            let selectedYears = repeatDays.filter { $0 >= 2025 }
            if !selectedYears.isEmpty {
                let calendar = Calendar.current
                let month = calendar.component(.month, from: date)
                let day = calendar.component(.day, from: date)
                let hour = calendar.component(.hour, from: date)
                let minute = calendar.component(.minute, from: date)
                let groupID = UUID()
                var scheduledIDs: [UUID] = []
                for year in selectedYears.sorted() {
                    var components = DateComponents()
                    components.year = year
                    components.month = month
                    components.day = day
                    components.hour = hour
                    components.minute = minute
                    components.second = 0
                    guard let yearDate = calendar.date(from: components), yearDate > Date() else { continue }
                    let recurringID = UUID()
                    var recurringSound = sound
                    if sourceExists {
                        let voiceFileName = "alarm_voice_\(recurringID.uuidString).caf"
                        let destURL = libraryURL.appendingPathComponent("Sounds/\(voiceFileName)")
                        try? FileManager.default.removeItem(at: destURL)
                        try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                        recurringSound = voiceFileName
                    }
                    _ = try await scheduleAlarmWithID(id: recurringID, date: yearDate, label: title, sound: recurringSound)
                    scheduledIDs.append(recurringID)
                    print("✅ Yearly alarm set for \(year) at \(yearDate)")
                }
                saveGroup(groupID: groupID, alarmIDs: scheduledIDs, label: title, repeatDays: repeatDays, calendarEnabled: calendarEnabled)
                UserDefaults.standard.set(sound, forKey: "alarmSound_\(groupID.uuidString)")
                await syncCalendarIfNeeded(groupID: groupID, title: title, repeatDays: repeatDays)
                rebuildGroups()
                saveNextAlarmForWidget()
                backupToiCloudDebounced()
                return scheduledIDs.first
            }

            if repeatDays.isEmpty {
                let id = try await scheduleAlarmWithID(id: alarmID, date: date, label: title, sound: finalSound)
                saveGroup(groupID: id, alarmIDs: [id], label: title, repeatDays: [], calendarEnabled: calendarEnabled)
                // ✅ Save sound so edit screen can load it
                UserDefaults.standard.set(sound, forKey: "alarmSound_\(id.uuidString)")
                await syncCalendarIfNeeded(groupID: id, title: title, repeatDays: [])
                rebuildGroups()
                saveNextAlarmForWidget()
                backupToiCloudDebounced()
                return id
            } else {
                let calendar = Calendar.current
                let timeComponents = calendar.dateComponents([.hour, .minute], from: date)
                let groupID = UUID()
                var scheduledIDs: [UUID] = []

                for weekday in repeatDays.sorted() {
                    let nextDate = nextDate(forWeekday: weekday, time: timeComponents)
                    let recurringID = UUID()

                    var recurringSound = sound
                    if sourceExists {
                        let voiceFileName = "alarm_voice_\(recurringID.uuidString).caf"
                        let destURL = libraryURL.appendingPathComponent("Sounds/\(voiceFileName)")
                        try? FileManager.default.removeItem(at: destURL)
                        try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                        recurringSound = voiceFileName
                        print("✅ Voice file copied for recurring alarm: \(voiceFileName)")
                    }

                    _ = try await scheduleAlarmWithID(id: recurringID, date: nextDate, label: title, sound: recurringSound)
                    scheduledIDs.append(recurringID)
                    print("✅ Recurring alarm set for weekday \(weekday) at \(nextDate)")
                }

                saveGroup(groupID: groupID, alarmIDs: scheduledIDs, label: title, repeatDays: repeatDays, calendarEnabled: calendarEnabled)
                UserDefaults.standard.set(sound, forKey: "alarmSound_\(groupID.uuidString)")
                await syncCalendarIfNeeded(groupID: groupID, title: title, repeatDays: repeatDays)
                rebuildGroups()
                saveNextAlarmForWidget()
                backupToiCloudDebounced()
                return scheduledIDs.first
            }
        } catch {
            print("Schedule alarm error:", error)
            return nil
        }
    }

    @discardableResult
    func scheduleAlarmWithID(id: UUID, date: Date, label: String, sound: String = "nokia.caf") async throws -> UUID {
        let scheduleDate = max(date, Date().addingTimeInterval(1))
        await LiveActivityCoordinator.endAlarmActivities()
        let presentation = makeAlarmPresentation(title: label)
        let attributes: AlarmAttributes<AlarmLiveActivityMetadata> = AlarmAttributes(
            presentation: presentation,
            metadata: AlarmLiveActivityMetadata(title: label, icon: "alarm.fill"),
            tintColor: .orange
        )
        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: snoozeDuration(for: id)),
            schedule: .fixed(scheduleDate),
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: id.uuidString),
            secondaryIntent: nil,
            sound: .named(sound)
        )
        let alarm = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        saveStoredFireDate(scheduleDate, for: id)
        saveLabel(label, for: id)
        upsertAlarmInList(alarm, label: label)
        NotificationService.shared.scheduleNotifications(for: id, label: label, fireDate: scheduleDate)
        return id
    }

    func deleteVoiceFile(for alarmID: String) {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let voiceURL = libraryURL.appendingPathComponent("Sounds/alarm_voice_\(alarmID).caf")
        try? FileManager.default.removeItem(at: voiceURL)
        print("🗑️ Deleted voice file for alarm: \(alarmID)")
    }

    func saveNextAlarmForWidget() {
        let userDefaults = UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")

        // ✅ Sync 24hr setting to App Group so widget can read it
        let use24Hour = UserDefaults.standard.bool(forKey: "use24HourFormat")
        userDefaults?.set(use24Hour, forKey: "use24HourFormat")

        // ✅ Get all future enabled alarms with repeating flag
        let futureAlarms = alarms
            .filter { $0.isEnabled }
            .compactMap { item -> (Date, String, Bool)? in
                guard let fireDate = item.fireDate, fireDate > Date() else { return nil }
                let groupID = getGroupID(for: item.id) ?? item.id
                let repeatDays = getRepeatDays(forGroup: groupID)
                let isRepeating = !repeatDays.isEmpty
                return (fireDate, item.label, isRepeating)
            }
            .sorted { $0.0 < $1.0 }

        // ✅ Split one-time and repeating
        let oneTimeAlarms = futureAlarms.filter { !$0.2 }
        let repeatingAlarms = futureAlarms.filter { $0.2 }

        // ✅ Priority: one-time first, repeating only if no one-time in next 3 days
        let threeDaysFromNow = Date().addingTimeInterval(3 * 24 * 3600)
        let upcomingOneTime = oneTimeAlarms.filter { $0.0 <= threeDaysFromNow }

        let combinedAlarms: [(Date, String)]
        if upcomingOneTime.isEmpty {
            combinedAlarms = futureAlarms.map { ($0.0, $0.1) }
        } else {
            let oneTimeMapped = oneTimeAlarms.map { ($0.0, $0.1) }
            let repeatingMapped = repeatingAlarms.map { ($0.0, $0.1) }
            combinedAlarms = (oneTimeMapped + repeatingMapped).sorted { $0.0 < $1.0 }
        }

        // ✅ Save next alarm
        if let first = combinedAlarms.first {
            userDefaults?.set(first.0.timeIntervalSince1970, forKey: "widgetNextAlarmDate")
            userDefaults?.set(first.1, forKey: "widgetNextAlarmLabel")
            print("✅ Widget saved: \(first.1) at \(first.0)")
        } else {
            userDefaults?.removeObject(forKey: "widgetNextAlarmDate")
            userDefaults?.removeObject(forKey: "widgetNextAlarmLabel")
            print("✅ Widget cleared — no active alarms")
        }

        // ✅ Save upcoming list (max 5)
        let upcomingList = combinedAlarms.prefix(5).map { (date, label) -> [String: Any] in
            return [
                "date": date.timeIntervalSince1970,
                "label": label
            ]
        }
        if let jsonData = try? JSONSerialization.data(withJSONObject: upcomingList),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            userDefaults?.set(jsonString, forKey: "widgetUpcomingAlarms")
        } else {
            userDefaults?.removeObject(forKey: "widgetUpcomingAlarms")
        }

        userDefaults?.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - iCloud Recordings Backup
    private func iCloudRecordingsURL() -> URL? {
        guard let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: "iCloud.com.speshtalent.FutureAlarm26"
        ) else { return nil }
        let recordingsURL = containerURL.appendingPathComponent("Documents/Recordings")
        try? FileManager.default.createDirectory(at: recordingsURL, withIntermediateDirectories: true)
        return recordingsURL
    }

    func uploadRecordingToiCloud(fileName: String, name: String) {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let localURL = libraryURL.appendingPathComponent("Sounds/\(fileName)")
        guard FileManager.default.fileExists(atPath: localURL.path),
              let cloudDir = iCloudRecordingsURL() else { return }
        let cloudURL = cloudDir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: cloudURL)
        try? FileManager.default.copyItem(at: localURL, to: cloudURL)
        // ✅ Save metadata to iCloud key-value store
        let store = NSUbiquitousKeyValueStore.default
        var recordings = store.array(forKey: "customRecordingsList") as? [[String: String]] ?? []
        if !recordings.contains(where: { $0["file"] == fileName }) {
            recordings.append(["name": name, "file": fileName])
            store.set(recordings, forKey: "customRecordingsList")
            store.synchronize()
        }
        print("✅ Recording uploaded to iCloud: \(fileName)")
    }

    func downloadRecordingsFromiCloud() {
        guard let cloudDir = iCloudRecordingsURL() else { return }
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let soundsURL = libraryURL.appendingPathComponent("Sounds")
        try? FileManager.default.createDirectory(at: soundsURL, withIntermediateDirectories: true)

        // ✅ Get recording list from iCloud key-value store
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()
        let cloudRecordings = store.array(forKey: "customRecordingsList") as? [[String: String]] ?? []

        // ✅ Merge with local list
        var localRecordings = UserDefaults.standard.array(forKey: "customRecordingsList") as? [[String: String]] ?? []
        let localFiles = Set(localRecordings.compactMap { $0["file"] })

        for recording in cloudRecordings {
            guard let fileName = recording["file"], let name = recording["name"] else { continue }
            // ✅ Download file if not already local
            if !localFiles.contains(fileName) {
                let cloudURL = cloudDir.appendingPathComponent(fileName)
                let localURL = soundsURL.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: cloudURL.path) {
                    try? FileManager.default.copyItem(at: cloudURL, to: localURL)
                    localRecordings.append(["name": name, "file": fileName])
                    print("✅ Recording downloaded from iCloud: \(fileName)")
                } else {
                    // ✅ Trigger iCloud download
                    try? FileManager.default.startDownloadingUbiquitousItem(at: cloudURL)
                }
            }
        }
        UserDefaults.standard.set(localRecordings, forKey: "customRecordingsList")
        print("✅ iCloud recordings sync complete")
    }
    // MARK: - iCloud Backup
    func backupToiCloudDebounced() {
        backupWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.backupToiCloud()
        }

        backupWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func backupToiCloud() {
        let store = NSUbiquitousKeyValueStore.default
        let cloudAlarms = alarmGroups.compactMap { group -> CloudAlarm? in
            guard let fireDate = group.fireDate else { return nil }
            let savedSound = UserDefaults.standard.string(forKey: "alarmSound_\(group.id.uuidString)") ?? "nokia.caf"
            return CloudAlarm(
                id: group.id.uuidString,
                label: group.label,
                fireDate: fireDate.timeIntervalSince1970,
                repeatDays: Array(group.repeatDays).sorted(),
                isEnabled: group.isEnabled,
                sound: savedSound,
                calendarEnabled: isCalendarEnabled(forGroup: group.id)
            )
        }

        do {
            let data = try JSONEncoder().encode(cloudAlarms)
            store.set(data, forKey: iCloudAlarmsKey)
            // ✅ Also backup custom recordings list
            let recordings = UserDefaults.standard.array(forKey: "customRecordingsList") ?? []
            store.set(recordings, forKey: "customRecordingsList")
            store.synchronize()
            print("✅ iCloud backup success: \(cloudAlarms.count) alarms saved")
        } catch {
            print("⚠️ iCloud backup failed: \(error)")
        }
    }

    func hasPendingCloudRestore() -> Bool {
        UserDefaults.standard.data(forKey: pendingCloudRestoreKey) != nil
    }

    func pendingCloudRestoreRequiresAuthorization() -> Bool {
        hasPendingCloudRestore() && AlarmManager.shared.authorizationState != .authorized
    }

    @discardableResult
    func restoreFromiCloudIfNeeded() async -> Bool {
        if !UserDefaults.standard.bool(forKey: hasLaunchedBeforeKey) {
            let store = NSUbiquitousKeyValueStore.default
            store.synchronize()

            guard let data = store.data(forKey: iCloudAlarmsKey) else {
                UserDefaults.standard.set(true, forKey: hasLaunchedBeforeKey)
                print("ℹ️ No iCloud alarm backup found")
                return false
            }

            let cloudAlarms: [CloudAlarm]
            do {
                cloudAlarms = try JSONDecoder().decode([CloudAlarm].self, from: data)
            } catch {
                UserDefaults.standard.set(true, forKey: hasLaunchedBeforeKey)
                print("⚠️ Invalid iCloud alarm backup; skipping restore")
                return false
            }

            guard !cloudAlarms.isEmpty else {
                UserDefaults.standard.set(true, forKey: hasLaunchedBeforeKey)
                print("ℹ️ iCloud alarm backup is empty")
                return false
            }

            savePendingCloudRestore(cloudAlarms)
            UserDefaults.standard.set(true, forKey: hasLaunchedBeforeKey)
            print("☁️ Cached \(cloudAlarms.count) alarms from iCloud backup for local restore")
        }
        // ✅ Download recordings from iCloud
        downloadRecordingsFromiCloud()
        return await restorePendingCloudBackupIfPossible()
    }

    @discardableResult
    func restorePendingCloudBackupIfPossible() async -> Bool {
        guard let cloudAlarms = loadPendingCloudRestore() else {
            return false
        }

        guard AlarmManager.shared.authorizationState == .authorized else {
            print("⚠️ iCloud backup fetched, but alarm restore is waiting for AlarmKit authorization")
            return false
        }

        print("🔄 Restoring \(cloudAlarms.count) alarms from cached iCloud backup")
        var restoredCount = 0

        for cloudAlarm in cloudAlarms {
            let fireDate = Date(timeIntervalSince1970: cloudAlarm.fireDate)
            let repeatDays = Set(cloudAlarm.repeatDays)

            if fireDate <= Date() && repeatDays.isEmpty {
                restorePastAlarmAsDisabled(cloudAlarm)
                restoredCount += 1
                print("⏭ Restored past one-time alarm as disabled: \(cloudAlarm.label)")
                continue
            }

            // ✅ Skip if alarm with same label and date already exists
            let alreadyExists = alarmGroups.contains { group in
                group.label == cloudAlarm.label &&
                abs((group.fireDate?.timeIntervalSince1970 ?? 0) - cloudAlarm.fireDate) < 60
            }
            // ✅ Also check AlarmKit directly for duplicates
            let alarmKitDuplicate = (try? AlarmManager.shared.alarms)?.contains { alarm in
                guard let schedule = alarm.schedule,
                      case let .fixed(date) = schedule else { return false }
                let label = loadLabels()[alarm.id.uuidString] ?? ""
                return label == cloudAlarm.label &&
                       abs(date.timeIntervalSince1970 - cloudAlarm.fireDate) < 60
            } ?? false

            if alreadyExists || alarmKitDuplicate {
                print("⏭ Skipping duplicate alarm: \(cloudAlarm.label)")
                continue
            }

            let restoreSound = cloudAlarm.sound ?? "nokia.caf"
            guard let restoredAlarmID = await scheduleFutureAlarm(
                date: fireDate,
                title: cloudAlarm.label,
                sound: restoreSound,
                repeatDays: repeatDays,
                calendarEnabled: cloudAlarm.calendarEnabled ?? false
            ) else {
                continue
            }

            // ✅ Save sound key for restored alarm so edit screen can load it
            let restoredGroupID = getGroupID(for: restoredAlarmID) ?? restoredAlarmID
            UserDefaults.standard.set(restoreSound, forKey: "alarmSound_\(restoredGroupID.uuidString)")
            UserDefaults.standard.set(restoreSound, forKey: "alarmSound_\(restoredAlarmID.uuidString)")

            if !cloudAlarm.isEnabled {
                let groupID = getGroupID(for: restoredAlarmID) ?? restoredAlarmID
                let alarmIDs = getAlarmIDs(forGroup: groupID)
                let idsToDisable = alarmIDs.isEmpty ? [restoredAlarmID] : alarmIDs

                for alarmID in idsToDisable {
                    if alarms.first(where: { $0.id == alarmID })?.isEnabled == true {
                        toggleAlarm(id: alarmID)
                    }
                }
            }

            restoredCount += 1
        }

        clearPendingCloudRestore()
        print("✅ iCloud restore complete: \(restoredCount) alarms restored")
        return restoredCount > 0
    }

    private func restorePastAlarmAsDisabled(_ cloudAlarm: CloudAlarm) {
        guard let alarmID = UUID(uuidString: cloudAlarm.id) else { return }

        let fireDate = Date(timeIntervalSince1970: cloudAlarm.fireDate)
        saveStoredFireDate(fireDate, for: alarmID)
        saveLabel(cloudAlarm.label, for: alarmID)
        saveGroup(
            groupID: alarmID,
            alarmIDs: [alarmID],
            label: cloudAlarm.label,
            repeatDays: Set(cloudAlarm.repeatDays),
            calendarEnabled: cloudAlarm.calendarEnabled ?? false
        )
        saveDisabledState(id: alarmID, disabled: true)
        removeFiredAlarm(alarmID: alarmID.uuidString)
        alarms.removeAll { $0.id == alarmID }
        alarms.append(AlarmListItem(id: alarmID, label: cloudAlarm.label, isEnabled: false, fireDate: fireDate))
        alarms.sort { lhs, rhs in
            (lhs.fireDate ?? .distantFuture) < (rhs.fireDate ?? .distantFuture)
        }
    }

    private func loadPendingCloudRestore() -> [CloudAlarm]? {
        guard let data = UserDefaults.standard.data(forKey: pendingCloudRestoreKey) else {
            return nil
        }

        let cloudAlarms: [CloudAlarm]
        do {
            cloudAlarms = try JSONDecoder().decode([CloudAlarm].self, from: data)
        } catch {
            clearPendingCloudRestore()
            print("⚠️ Pending iCloud restore data was invalid and has been cleared")
            return nil
        }
        return cloudAlarms
    }

    private func savePendingCloudRestore(_ cloudAlarms: [CloudAlarm]) {
        do {
            let data = try JSONEncoder().encode(cloudAlarms)
            UserDefaults.standard.set(data, forKey: pendingCloudRestoreKey)
        } catch {
            print("⚠️ Failed to cache iCloud alarm restore data: \(error)")
        }
    }

    private func clearPendingCloudRestore() {
        UserDefaults.standard.removeObject(forKey: pendingCloudRestoreKey)
    }

    // MARK: - Group persistence
    private func saveGroup(groupID: UUID, alarmIDs: [UUID], label: String, repeatDays: Set<Int>, calendarEnabled: Bool) {
        var groups = loadGroupIDs()
        groups[groupID.uuidString] = alarmIDs.map { $0.uuidString }
        UserDefaults.standard.set(groups, forKey: groupIDsKey)

        var labels = loadLabels()
        labels[groupID.uuidString] = label
        UserDefaults.standard.set(labels, forKey: labelsStoreKey)

        var repeatDict = loadGroupRepeatDays()
        repeatDict[groupID.uuidString] = Array(repeatDays)
        UserDefaults.standard.set(repeatDict, forKey: groupRepeatDaysKey)

        var calendarDict = loadGroupCalendarEnabled()
        calendarDict[groupID.uuidString] = calendarEnabled
        UserDefaults.standard.set(calendarDict, forKey: groupCalendarEnabledKey)

        var alarmToGroup = loadAlarmToGroup()
        for alarmID in alarmIDs {
            alarmToGroup[alarmID.uuidString] = groupID.uuidString
        }
        UserDefaults.standard.set(alarmToGroup, forKey: alarmToGroupKey)
    }

    private func removeGroup(groupID: UUID) {
        var groups = loadGroupIDs()
        let alarmIDStrs = groups[groupID.uuidString] ?? []
        groups.removeValue(forKey: groupID.uuidString)
        UserDefaults.standard.set(groups, forKey: groupIDsKey)

        var repeatDict = loadGroupRepeatDays()
        repeatDict.removeValue(forKey: groupID.uuidString)
        UserDefaults.standard.set(repeatDict, forKey: groupRepeatDaysKey)

        var calendarDict = loadGroupCalendarEnabled()
        calendarDict.removeValue(forKey: groupID.uuidString)
        UserDefaults.standard.set(calendarDict, forKey: groupCalendarEnabledKey)

        var alarmToGroup = loadAlarmToGroup()
        for idStr in alarmIDStrs {
            alarmToGroup.removeValue(forKey: idStr)
        }
        UserDefaults.standard.set(alarmToGroup, forKey: alarmToGroupKey)
    }

    func getGroupID(for alarmID: UUID) -> UUID? {
        let dict = loadAlarmToGroup()
        guard let groupIDStr = dict[alarmID.uuidString] else { return nil }
        return UUID(uuidString: groupIDStr)
    }

    func getAlarmIDs(forGroup groupID: UUID) -> [UUID] {
        let dict = loadGroupIDs()
        return (dict[groupID.uuidString] ?? []).compactMap { UUID(uuidString: $0) }
    }

    func getRepeatDays(forGroup groupID: UUID) -> Set<Int> {
        let dict = loadGroupRepeatDays()
        return Set(dict[groupID.uuidString] ?? [])
    }

    func isCalendarEnabled(forGroup groupID: UUID) -> Bool {
        loadGroupCalendarEnabled()[groupID.uuidString] ?? false
    }

    private func loadGroupIDs() -> [String: [String]] {
        UserDefaults.standard.dictionary(forKey: groupIDsKey) as? [String: [String]] ?? [:]
    }

    private func loadAlarmToGroup() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: alarmToGroupKey) as? [String: String] ?? [:]
    }

    private func loadGroupRepeatDays() -> [String: [Int]] {
        UserDefaults.standard.dictionary(forKey: groupRepeatDaysKey) as? [String: [Int]] ?? [:]
    }

    private func loadGroupCalendarEnabled() -> [String: Bool] {
        UserDefaults.standard.dictionary(forKey: groupCalendarEnabledKey) as? [String: Bool] ?? [:]
    }

    private func syncCalendarIfNeeded(groupID: UUID, title: String, repeatDays: Set<Int>) async {
        guard isCalendarEnabled(forGroup: groupID) else { return }

        let alarmIDs = getAlarmIDs(forGroup: groupID)
        let idsToSync = alarmIDs.isEmpty ? [groupID] : alarmIDs
        let isWeekly = repeatDays.contains { $0 >= 1 && $0 <= 7 }

        for alarmID in idsToSync {
            guard let fireDate = alarms.first(where: { $0.id == alarmID })?.fireDate else { continue }
            let key = fireDate.timeIntervalSince1970.description
            CalendarService.shared.removeAlarmFromCalendar(alarmID: key)

            // WHY: Monthly groups fan out into multiple concrete dates, so syncing each future
            // month keeps calendar output aligned with the alarm instances the user actually expects.
            if !isWeekly &&
                repeatDays.contains(where: { $0 >= 1 && $0 <= 31 }) &&
                !repeatDays.contains(where: { $0 >= 2025 }) {
                let day = repeatDays.filter { $0 >= 1 && $0 <= 31 }.first ?? Calendar.current.component(.day, from: fireDate)
                let cal = Calendar.current
                let currentMonth = cal.component(.month, from: Date())
                let currentYear = cal.component(.year, from: Date())
                let selectedMonths = repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted()
                let monthsToUse: [Int] = selectedMonths.isEmpty
                    ? Array(currentMonth...12)
                    : selectedMonths.map { $0 - 100 }.filter { $0 >= currentMonth }

                for month in monthsToUse {
                    var comps = DateComponents()
                    comps.year = currentYear
                    comps.month = month
                    comps.day = day
                    comps.hour = cal.component(.hour, from: fireDate)
                    comps.minute = cal.component(.minute, from: fireDate)
                    if let eventDate = cal.date(from: comps), eventDate > Date() {
                        let monthAlarmID = eventDate.timeIntervalSince1970.description
                        CalendarService.shared.removeAlarmFromCalendar(alarmID: monthAlarmID)
                        _ = await CalendarService.shared.addAlarmToCalendar(
                            title: title,
                            date: eventDate,
                            alarmID: monthAlarmID
                        )
                    }
                }
                continue
            }

            let weekday = isWeekly ? Calendar.current.component(.weekday, from: fireDate) : nil
            _ = await CalendarService.shared.addAlarmToCalendar(
                title: title,
                date: fireDate,
                alarmID: key,
                weekday: weekday
            )
        }
    }

    private func nextDate(forWeekday weekday: Int, time: DateComponents) -> Date {
        let calendar = Calendar.current
        var components = DateComponents()
        components.weekday = weekday
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        guard let next = calendar.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime) else {
            return Date().addingTimeInterval(3600)
        }
        return next
    }

    private func nextEnabledOneTimeDate(from storedDate: Date) -> Date {
        guard storedDate <= Date() else { return storedDate }

        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: storedDate)

        return calendar.nextDate(
            after: Date(),
            matching: timeComponents,
            matchingPolicy: .nextTimePreservingSmallerComponents
        ) ?? Date().addingTimeInterval(60)
    }

    private func loadDisabledIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: disabledAlarmsKey) ?? [])
    }

    private func saveDisabledState(id: UUID, disabled: Bool) {
        var ids = loadDisabledIDs()
        if disabled { ids.insert(id.uuidString) } else { ids.remove(id.uuidString) }
        UserDefaults.standard.set(Array(ids), forKey: disabledAlarmsKey)
    }

    private func removeFromDisabled(id: UUID) {
        var ids = loadDisabledIDs()
        ids.remove(id.uuidString)
        UserDefaults.standard.set(Array(ids), forKey: disabledAlarmsKey)
    }

    private func saveStoredFireDate(_ date: Date, for id: UUID) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "disabledAlarmDate_\(id.uuidString)")
    }

    private func removeStoredFireDate(for id: UUID) {
        UserDefaults.standard.removeObject(forKey: "disabledAlarmDate_\(id.uuidString)")
    }

    private func loadLabels() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: labelsStoreKey) as? [String: String] ?? [:]
    }

    private func saveLabel(_ label: String, for id: UUID) {
        var labels = loadLabels()
        labels[id.uuidString] = label
        UserDefaults.standard.set(labels, forKey: labelsStoreKey)

        // ✅ Also save to App Group so StopAlarmIntent can read labels
        let appGroup = UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")
        appGroup?.set(labels, forKey: labelsStoreKey)
    }

    private func removeLabel(for id: UUID) {
        var labels = loadLabels()
        labels.removeValue(forKey: id.uuidString)
        UserDefaults.standard.set(labels, forKey: labelsStoreKey)
    }

    private func upsertAlarmInList(_ alarm: Alarm, label: String) {
        alarms.removeAll { $0.id == alarm.id }
        alarms.append(AlarmListItem(alarm: alarm, label: label, isEnabled: true))
        alarms.sort { lhs, rhs in
            (lhs.fireDate ?? .distantFuture) < (rhs.fireDate ?? .distantFuture)
        }
    }

    // ✅ HISTORY
    private let historyKey = "AlarmHistory"

    func saveToHistory(alarmID: String, label: String, firedAt: Date) {
        var history = loadHistory()
        let entry: [String: Any] = [
            "alarmID": alarmID,
            "label": label,
            "firedAt": firedAt.timeIntervalSince1970
        ]
        history.insert(entry, at: 0)
        if history.count > 50 { history = Array(history.prefix(50)) }
        if let data = try? JSONSerialization.data(withJSONObject: history),
           let json = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(json, forKey: historyKey)
            UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")?.set(json, forKey: historyKey)
        }
    }
    // ✅ Save fired one-time alarm
    func saveFiredAlarm(alarmID: String, label: String, firedAt: Date) {
        var fired = loadFiredAlarms()
        fired[alarmID] = [
            "label": label,
            "firedAt": firedAt.timeIntervalSince1970
        ]
        if let data = try? JSONSerialization.data(withJSONObject: fired),
           let json = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(json, forKey: "FiredOneTimeAlarms")
        }
    }

    func loadFiredAlarms() -> [String: [String: Any]] {
        var fired: [String: [String: Any]] = [:]
        
        // ✅ Load manually saved fired alarms
        if let json = UserDefaults.standard.string(forKey: "FiredOneTimeAlarms"),
           let data = json.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            fired = dict
        }

        // ✅ Auto-detect fired one-time alarms from AlarmKit
        let activeAlarmIDs = Set((try? AlarmManager.shared.alarms)?.map { $0.id.uuidString } ?? [])
        let groupIDs = UserDefaults.standard.dictionary(forKey: groupIDsKey) as? [String: [String]] ?? [:]
        let repeatDaysDict = UserDefaults.standard.dictionary(forKey: groupRepeatDaysKey) as? [String: [Int]] ?? [:]
        let labels = loadLabels()

        for (groupIDStr, alarmIDStrs) in groupIDs {
            // ✅ Skip if has repeat days OR if repeat days key doesn't exist (safety check)
            let repeatDays = repeatDaysDict[groupIDStr] ?? []
            guard repeatDays.isEmpty else { continue }
            // ✅ Also skip if group has more than 1 alarm ID (weekly groups have multiple)
            guard alarmIDStrs.count == 1 else { continue }
            guard fired[groupIDStr] == nil else { continue }
            guard !alarmIDStrs.isEmpty else { continue }
            // ✅ Skip if any alarm ID is in disabled list (not fired, just disabled)
            let disabledIDs = loadDisabledIDs()
            let allDisabled = alarmIDStrs.allSatisfy { disabledIDs.contains($0) }
            guard alarmIDStrs.allSatisfy({ !activeAlarmIDs.contains($0) }) else { continue }
            guard !allDisabled else { continue }
            let label = labels[groupIDStr] ?? "Alarm"
            fired[groupIDStr] = ["label": label, "firedAt": Date().timeIntervalSince1970]
            // ✅ Save it so it persists
            if let data = try? JSONSerialization.data(withJSONObject: fired),
               let json = String(data: data, encoding: .utf8) {
                UserDefaults.standard.set(json, forKey: "FiredOneTimeAlarms")
            }
        }

        return fired
    }

    func removeFiredAlarm(alarmID: String) {
        var fired = loadFiredAlarms()
        fired.removeValue(forKey: alarmID)
        if let data = try? JSONSerialization.data(withJSONObject: fired),
           let json = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(json, forKey: "FiredOneTimeAlarms")
        }
    }

    func loadHistory() -> [[String: Any]] {
        let appGroup = UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")
        let json = appGroup?.string(forKey: "AlarmHistory")
                   ?? UserDefaults.standard.string(forKey: "AlarmHistory")
        guard let json,
              let data = json.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return list
    }

    func clearHistory() {
            UserDefaults.standard.removeObject(forKey: historyKey)
        }

        func rescheduleIfFired() {
            let groupIDsDict = loadGroupIDs()
            let repeatDaysDict = loadGroupRepeatDays()
            let labels = loadLabels()
            let activeAlarmIDs = Set((try? AlarmManager.shared.alarms)?.map { $0.id.uuidString } ?? [])
            let disabledIDs = loadDisabledIDs()

            for (groupIDStr, alarmIDStrs) in groupIDsDict {
                let repeatDays = Set(repeatDaysDict[groupIDStr] ?? [])
                guard !repeatDays.isEmpty else { continue }

                let allGone = alarmIDStrs.allSatisfy { !activeAlarmIDs.contains($0) }
                let anyFired = alarmIDStrs.contains { !activeAlarmIDs.contains($0) && !disabledIDs.contains($0) }
                let allDisabled = alarmIDStrs.allSatisfy { disabledIDs.contains($0) }
                guard (allGone || anyFired) && !allDisabled else { continue }

                // ✅ Prevent rescheduling same group more than once per 60 seconds
                let lastRescheduleKey = "lastReschedule_\(groupIDStr)"
                let lastReschedule = UserDefaults.standard.double(forKey: lastRescheduleKey)
                let secondsSinceReschedule = Date().timeIntervalSince1970 - lastReschedule
                guard secondsSinceReschedule > 60 else { continue }
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastRescheduleKey)

                guard let groupUUID = UUID(uuidString: groupIDStr) else { continue }
                let label = labels[groupIDStr] ?? "Alarm"
                let savedSound = UserDefaults.standard.string(forKey: "alarmSound_\(groupIDStr)") ?? "nokia.caf"
                let savedInterval = alarmIDStrs.compactMap {
                    UserDefaults.standard.object(forKey: "disabledAlarmDate_\($0)") as? TimeInterval
                }.first ?? 0
                let originalDate = savedInterval > 0 ? Date(timeIntervalSince1970: savedInterval) : Date()
                let hour = Calendar.current.component(.hour, from: originalDate)
                let minute = Calendar.current.component(.minute, from: originalDate)

                let isWeekly = repeatDays.allSatisfy { $0 >= 1 && $0 <= 7 }
                let isYearly = repeatDays.contains { $0 >= 2025 }
                let isMonthly = !isWeekly && !isYearly

                // ✅ Save history per individually fired alarm
                for alarmIDStr in alarmIDStrs {
                    if !activeAlarmIDs.contains(alarmIDStr) && !disabledIDs.contains(alarmIDStr) {
                        AlarmService.shared.saveToHistory(alarmID: alarmIDStr, label: label, firedAt: Date())
                    }
                }

                // ✅ Weekly — only reschedule fired day, keep others alive
                if isWeekly {
                    let firedAlarmIDs = alarmIDStrs.filter {
                        !activeAlarmIDs.contains($0) && !disabledIDs.contains($0)
                    }
                    let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: originalDate)
                    Task {
                        let cal = Calendar.current
                        let now = Date()
                        for firedIDStr in firedAlarmIDs {
                            guard let firedUUID = UUID(uuidString: firedIDStr) else { continue }
                            let savedInterval = UserDefaults.standard.object(forKey: "disabledAlarmDate_\(firedIDStr)") as? TimeInterval ?? Date().timeIntervalSince1970
                            let firedDate = Date(timeIntervalSince1970: savedInterval)
                            let weekday = cal.component(.weekday, from: firedDate)
                            var comps = DateComponents()
                            comps.weekday = weekday
                            comps.hour = timeComponents.hour
                            comps.minute = timeComponents.minute
                            guard let nextOccurrence = cal.nextDate(after: now, matching: comps, matchingPolicy: .nextTime) else { continue }
                            do { try AlarmManager.shared.cancel(id: firedUUID) } catch {}
                            let newID = UUID()
                            _ = try? await scheduleAlarmWithID(id: newID, date: nextOccurrence, label: label, sound: savedSound)
                            saveLabel(label, for: newID)
                            var groups = loadGroupIDs()
                            if var groupAlarmIDs = groups[groupIDStr] {
                                groupAlarmIDs.removeAll { $0 == firedIDStr }
                                groupAlarmIDs.append(newID.uuidString)
                                groups[groupIDStr] = groupAlarmIDs
                                UserDefaults.standard.set(groups, forKey: groupIDsKey)
                                var alarmToGroup = loadAlarmToGroup()
                                alarmToGroup.removeValue(forKey: firedIDStr)
                                alarmToGroup[newID.uuidString] = groupIDStr
                                UserDefaults.standard.set(alarmToGroup, forKey: alarmToGroupKey)
                            }
                            print("✅ Rescheduled weekday \(weekday) to \(nextOccurrence)")
                        }
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        await MainActor.run { loadAlarms() }
                    }
                    continue
                }

                cancelAlarm(id: groupUUID)

                Task {
                    var nextDate: Date?
                    let cal = Calendar.current
                    let now = Date()

                    if isWeekly {
                        let timeComponents = cal.dateComponents([.hour, .minute], from: originalDate)
                        let nextWeekday = repeatDays.sorted().compactMap { weekday -> Date? in
                            var comps = DateComponents()
                            comps.weekday = weekday
                            comps.hour = timeComponents.hour
                            comps.minute = timeComponents.minute
                            return cal.nextDate(after: now, matching: comps, matchingPolicy: .nextTime)
                        }.min() ?? now.addingTimeInterval(7 * 24 * 3600)
                        _ = await scheduleFutureAlarm(
                            date: nextWeekday,
                            title: label,
                            sound: savedSound,
                            repeatDays: repeatDays,
                            calendarEnabled: isCalendarEnabled(forGroup: groupUUID)
                        )
                        print("✅ Auto-rescheduled weekly: \(label) for \(nextWeekday)")
                        return
                    } else if isMonthly {
                        let day = repeatDays.filter { $0 >= 1 && $0 <= 31 }.first ?? 1
                        let selectedMonths = repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted()
                        if selectedMonths.isEmpty {
                            let currentMonth = cal.component(.month, from: now)
                            let currentYear = cal.component(.year, from: now)
                            var comps = DateComponents()
                            comps.day = day
                            comps.hour = hour
                            comps.minute = minute
                            comps.month = currentMonth == 12 ? 1 : currentMonth + 1
                            comps.year = currentMonth == 12 ? currentYear + 1 : currentYear
                            nextDate = cal.date(from: comps)
                        } else {
                            let currentMonth = cal.component(.month, from: now)
                            let currentYear = cal.component(.year, from: now)
                            let futureMonths = selectedMonths.filter { $0 - 100 > currentMonth }
                            let targetMonth = futureMonths.first.map { $0 - 100 } ?? selectedMonths.first.map { $0 - 100 } ?? currentMonth
                            let targetYear = futureMonths.isEmpty ? currentYear + 1 : currentYear
                            var comps = DateComponents()
                            comps.day = day
                            comps.month = targetMonth
                            comps.year = targetYear
                            comps.hour = hour
                            comps.minute = minute
                            nextDate = cal.date(from: comps)
                        }
                    } else if isYearly {
                        let day = repeatDays.filter { $0 >= 1 && $0 <= 31 }.first ?? cal.component(.day, from: originalDate)
                        let months = repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted()
                        let month = months.first.map { $0 - 100 } ?? cal.component(.month, from: originalDate)
                        let years = repeatDays.filter { $0 >= 2025 }.sorted()
                        let currentYear = cal.component(.year, from: now)
                        guard let nextYear = years.first(where: { $0 > currentYear }) else { return }
                        var comps = DateComponents()
                        comps.year = nextYear
                        comps.month = month
                        comps.day = day
                        comps.hour = hour
                        comps.minute = minute
                        nextDate = cal.date(from: comps)
                    }

                    guard let nextDate = nextDate else { return }
                    _ = await scheduleFutureAlarm(
                        date: nextDate,
                        title: label,
                        sound: savedSound,
                        repeatDays: repeatDays,
                        calendarEnabled: isCalendarEnabled(forGroup: groupUUID)
                    )
                    print("✅ Auto-rescheduled \(label) for \(nextDate)")
                }
            }
        }
    }
