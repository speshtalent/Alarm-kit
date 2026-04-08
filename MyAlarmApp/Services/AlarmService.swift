import Foundation
import Combine
import AlarmKit
import ActivityKit
import SwiftUI
import AppIntents
import WidgetKit

@MainActor
final class AlarmService: ObservableObject {

    struct AlarmListItem: Identifiable {
        let alarm: Alarm
        let label: String
        var isEnabled: Bool

        var id: UUID { alarm.id }
        var fireDate: Date? {
            guard let schedule = alarm.schedule else { return nil }
            guard case let .fixed(date) = schedule else { return nil }
            return date
        }
    }

    struct AlarmGroup: Identifiable {
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
            if repeatDays.count == 7 { return "Every day" }
            if repeatDays == Set([2, 3, 4, 5, 6]) { return "Weekdays" }
            if repeatDays == Set([7, 1]) { return "Weekends" }
            return weekDays.filter { repeatDays.contains($0.value) }.map { $0.label }.joined(separator: ", ")
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
    private let iCloudAlarmsKey    = "iCloudSavedAlarms"

    private init() {}

    private func makeAlarmAlert(title: String) -> AlarmPresentation.Alert {
        let titleResource = LocalizedStringResource(stringLiteral: title)
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(
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
        } else {
            return AlarmPresentation.Alert(
                title: titleResource,
                stopButton: AlarmButton(
                    text: "Stop Alarm",
                    textColor: .white,
                    systemImageName: "alarm.fill"
                )
            )
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
        let alert = makeAlarmAlert(title: label)
        let presentation = AlarmPresentation(alert: alert)
        let attributes: AlarmAttributes<AppAlarmMetadata> = AlarmAttributes(
            presentation: presentation,
            metadata: AppAlarmMetadata(title: label, icon: "alarm"),
            tintColor: .orange
        )
        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: nil,
            schedule: .fixed(scheduleDate),
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: id.uuidString),
            secondaryIntent: RepeatAlarmIntent(alarmID: id.uuidString),
            sound: .named(sound)
        )
        let alarm = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        saveLabel(label, for: id)
        upsertAlarmInList(alarm, label: label)
        return id
    }

    func cancelAlarm(id: UUID) {
        let groupID = getGroupID(for: id) ?? id
        let groupAlarmIDs = getAlarmIDs(forGroup: groupID)
        let idsToCancel = groupAlarmIDs.isEmpty ? [id] : groupAlarmIDs

        for alarmID in idsToCancel {
            if let item = alarms.first(where: { $0.id == alarmID }), let fireDate = item.fireDate {
                let key = fireDate.timeIntervalSince1970.description
                CalendarService.shared.removeAlarmFromCalendar(alarmID: key)
            }
            deleteVoiceFile(for: alarmID.uuidString)
            do {
                try AlarmManager.shared.cancel(id: alarmID)
            } catch {
                print("Cancel alarm error:", error)
            }
            removeLabel(for: alarmID)
            removeFromDisabled(id: alarmID)
            alarms.removeAll { $0.alarm.id == alarmID }
        }

        removeFiredAlarm(alarmID: groupID.uuidString)
        removeGroup(groupID: groupID)
        rebuildGroups()
        saveNextAlarmForWidget()
        syncToiCloud()
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
                try AlarmManager.shared.cancel(id: id)
                alarms[index] = AlarmListItem(alarm: item.alarm, label: item.label, isEnabled: false)
                saveDisabledState(id: id, disabled: true)
                print("⏸ Alarm disabled: \(id)")
            } catch {
                print("Disable alarm error:", error)
            }
            saveNextAlarmForWidget()
        } else {
            // ✅ Try to get fireDate from saved UserDefaults if nil
            let fireDate: Date
            print("🔍 item.fireDate: \(String(describing: item.fireDate))")
            print("🔍 savedInterval: \(String(describing: UserDefaults.standard.object(forKey: "disabledAlarmDate_\(id.uuidString)")))")
            if let fd = item.fireDate {
                fireDate = fd
            } else if let savedInterval = UserDefaults.standard.object(forKey: "disabledAlarmDate_\(id.uuidString)") as? TimeInterval {
                fireDate = Date(timeIntervalSince1970: savedInterval)
            } else {
                print("⚠️ No fire date found")
                return
            }
            Task {
                do {
                    let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                    let voiceFileName = "alarm_voice_\(id.uuidString).caf"
                    let voicePath = libraryURL.appendingPathComponent("Sounds/\(voiceFileName)").path
                    let sound = FileManager.default.fileExists(atPath: voicePath) ? voiceFileName : "nokia.caf"
                    try await scheduleAlarmWithID(id: id, date: fireDate, label: item.label, sound: sound)
                    alarms[index] = AlarmListItem(alarm: item.alarm, label: item.label, isEnabled: true)
                    saveDisabledState(id: id, disabled: false)
                    print("▶️ Alarm re-enabled with sound: \(sound)")
                } catch {
                    print("Re-enable alarm error:", error)
                }
                saveNextAlarmForWidget()
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

    func loadAlarms() {
        do {
            let all = try AlarmManager.shared.alarms
            let labels = loadLabels()
            let disabled = loadDisabledIDs()

            // ✅ Active alarms from AlarmKit
            var loadedAlarms = all
                .filter { $0.schedule != nil }
                .map { alarm in
                    AlarmListItem(
                        alarm: alarm,
                        label: labels[alarm.id.uuidString] ?? "Alarm",
                        isEnabled: !disabled.contains(alarm.id.uuidString)
                    )
                }

            // ✅ Add disabled alarms that are not in AlarmKit anymore
            let activeIDs = Set(loadedAlarms.map { $0.id.uuidString })
            for disabledID in disabled {
                if !activeIDs.contains(disabledID),
                   let savedInterval = UserDefaults.standard.object(forKey: "disabledAlarmDate_\(disabledID)") as? TimeInterval,
                   let _ = UUID(uuidString: disabledID) {
                    let fireDate = Date(timeIntervalSince1970: savedInterval)
                    guard fireDate > Date() else { continue }
                    let label = labels[disabledID] ?? "Alarm"
                    if let existingAlarm = alarms.first(where: { $0.id.uuidString == disabledID }) {
                        loadedAlarms.append(AlarmListItem(alarm: existingAlarm.alarm, label: label, isEnabled: false))
                    }
                }
            }

            alarms = loadedAlarms.sorted { lhs, rhs in
                (lhs.fireDate ?? .distantFuture) < (rhs.fireDate ?? .distantFuture)
            }
        } catch {
            print("Load alarms error:", error)
            alarms = []
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            rebuildGroups()
            saveNextAlarmForWidget()
        }
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

        // ✅ Add fired one-time alarms as separate groups
        let firedAlarms = loadFiredAlarms()
        let existingIDs = Set(groups.map { $0.id.uuidString })
        for (alarmIDStr, info) in firedAlarms {
            guard !existingIDs.contains(alarmIDStr),
                  let groupID = UUID(uuidString: alarmIDStr),
                  let label = info["label"] as? String,
                  let firedAt = info["firedAt"] as? TimeInterval else { continue }
            groups.append(AlarmGroup(
                id: groupID,
                label: label,
                isEnabled: false,
                alarmIDs: [],
                fireDate: Date(timeIntervalSince1970: firedAt),
                repeatDays: [],
                isFired: true  // ✅
            ))
        }

        // ✅ Mark fired one-time alarms that are in groups
        for i in groups.indices {
            if firedAlarms[groups[i].id.uuidString] != nil {
                groups[i].isFired = true
            }
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
        repeatDays: Set<Int> = []
    ) async -> UUID? {
        do {
            let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            let tempURL = libraryURL.appendingPathComponent("Sounds/alarm_voice_temp.caf")
            let tempExists = FileManager.default.fileExists(atPath: tempURL.path)

            let alarmID = UUID()
            var finalSound = sound

            let isMonthly = repeatDays == Set([100]) || repeatDays.allSatisfy { $0 >= 101 && $0 <= 112 }
            let isYearly = repeatDays == Set([200]) || repeatDays.allSatisfy { $0 >= 2025 }
            if tempExists && (repeatDays.isEmpty || isMonthly || isYearly) {
                let voiceFileName = "alarm_voice_\(alarmID.uuidString).caf"
                let destURL = libraryURL.appendingPathComponent("Sounds/\(voiceFileName)")
                try? FileManager.default.removeItem(at: destURL)
                try? FileManager.default.copyItem(at: tempURL, to: destURL)
                finalSound = voiceFileName
                print("✅ Voice file saved as: \(voiceFileName)")
            }
            UserDefaults.standard.set(snoozeDuration, forKey: "snoozeDuration_\(alarmID.uuidString)")

            // ✅ Monthly — schedule single alarm, save with repeatDays Set([100])
            if repeatDays == Set([100]) {
                let id = try await scheduleAlarmWithID(id: alarmID, date: date, label: title, sound: finalSound)
                saveGroup(groupID: id, alarmIDs: [id], label: title, repeatDays: Set([100]))
                rebuildGroups()
                saveNextAlarmForWidget()
                syncToiCloud()
                return id
            }

            // ✅ Monthly with selected months (101-112)
            let selectedMonths = repeatDays.filter { $0 >= 101 && $0 <= 112 }
            if !selectedMonths.isEmpty {
                let calendar = Calendar.current
                let timeComponents = calendar.dateComponents([.hour, .minute], from: date)
                let dayOfMonth = calendar.component(.day, from: date)
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
                    let nextDate = calendar.nextDate(after: Date(), matching: components, matchingPolicy: .nextTimePreservingSmallerComponents) ?? date
                    let recurringID = UUID()
                    var recurringSound = sound
                    if tempExists {
                        let voiceFileName = "alarm_voice_\(recurringID.uuidString).caf"
                        let destURL = libraryURL.appendingPathComponent("Sounds/\(voiceFileName)")
                        try? FileManager.default.removeItem(at: destURL)
                        try? FileManager.default.copyItem(at: tempURL, to: destURL)
                        recurringSound = voiceFileName
                    }
                    _ = try await scheduleAlarmWithID(id: recurringID, date: nextDate, label: title, sound: recurringSound)
                    scheduledIDs.append(recurringID)
                    print("✅ Monthly alarm set for month \(monthNumber) at \(nextDate)")
                }
                saveGroup(groupID: groupID, alarmIDs: scheduledIDs, label: title, repeatDays: repeatDays)
                rebuildGroups()
                saveNextAlarmForWidget()
                syncToiCloud()
                return scheduledIDs.first
            }

            // ✅ Yearly — schedule single alarm, save with repeatDays Set([200])
            if repeatDays == Set([200]) {
                let id = try await scheduleAlarmWithID(id: alarmID, date: date, label: title, sound: finalSound)
                saveGroup(groupID: id, alarmIDs: [id], label: title, repeatDays: Set([200]))
                rebuildGroups()
                saveNextAlarmForWidget()
                syncToiCloud()
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
                    if tempExists {
                        let voiceFileName = "alarm_voice_\(recurringID.uuidString).caf"
                        let destURL = libraryURL.appendingPathComponent("Sounds/\(voiceFileName)")
                        try? FileManager.default.removeItem(at: destURL)
                        try? FileManager.default.copyItem(at: tempURL, to: destURL)
                        recurringSound = voiceFileName
                    }
                    _ = try await scheduleAlarmWithID(id: recurringID, date: yearDate, label: title, sound: recurringSound)
                    scheduledIDs.append(recurringID)
                    print("✅ Yearly alarm set for \(year) at \(yearDate)")
                }
                saveGroup(groupID: groupID, alarmIDs: scheduledIDs, label: title, repeatDays: repeatDays)
                rebuildGroups()
                saveNextAlarmForWidget()
                syncToiCloud()
                return scheduledIDs.first
            }

            if repeatDays.isEmpty {
                let id = try await scheduleAlarmWithID(id: alarmID, date: date, label: title, sound: finalSound)
                saveGroup(groupID: id, alarmIDs: [id], label: title, repeatDays: [])
                rebuildGroups()
                saveNextAlarmForWidget()
                syncToiCloud()
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
                    if tempExists {
                        let voiceFileName = "alarm_voice_\(recurringID.uuidString).caf"
                        let destURL = libraryURL.appendingPathComponent("Sounds/\(voiceFileName)")
                        try? FileManager.default.removeItem(at: destURL)
                        try? FileManager.default.copyItem(at: tempURL, to: destURL)
                        recurringSound = voiceFileName
                        print("✅ Voice file copied for recurring alarm: \(voiceFileName)")
                    }

                    _ = try await scheduleAlarmWithID(id: recurringID, date: nextDate, label: title, sound: recurringSound)
                    scheduledIDs.append(recurringID)
                    print("✅ Recurring alarm set for weekday \(weekday) at \(nextDate)")
                }

                saveGroup(groupID: groupID, alarmIDs: scheduledIDs, label: title, repeatDays: repeatDays)
                rebuildGroups()
                saveNextAlarmForWidget()
                syncToiCloud()
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
        let alert = makeAlarmAlert(title: label)
        let presentation = AlarmPresentation(alert: alert)
        let attributes: AlarmAttributes<AppAlarmMetadata> = AlarmAttributes(
            presentation: presentation,
            metadata: AppAlarmMetadata(title: label, icon: "alarm"),
            tintColor: .orange
        )
        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: nil,
            schedule: .fixed(scheduleDate),
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: id.uuidString),
            secondaryIntent: RepeatAlarmIntent(alarmID: id.uuidString),
            sound: .named(sound)
        )
        let alarm = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        saveLabel(label, for: id)
        upsertAlarmInList(alarm, label: label)
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

    // MARK: - iCloud Sync
    func syncToiCloud() {
        let store = NSUbiquitousKeyValueStore.default
        var iCloudData: [[String: Any]] = []

        for group in alarmGroups {
            guard let fireDate = group.fireDate else { continue }
            var entry: [String: Any] = [
                "groupID":    group.id.uuidString,
                "label":      group.label,
                "fireDate":   fireDate.timeIntervalSince1970,
                "repeatDays": Array(group.repeatDays),
                "isEnabled":  group.isEnabled,
                "alarmIDs":   group.alarmIDs.map { $0.uuidString },
                "sound":      "nokia.caf"
            ]
            if let firstID = group.alarmIDs.first {
                let labels = loadLabels()
                entry["label"] = labels[firstID.uuidString] ?? group.label
            }
            iCloudData.append(entry)
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: iCloudData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            store.set(jsonString, forKey: iCloudAlarmsKey)
            store.synchronize()
            print("✅ iCloud sync: \(iCloudData.count) alarm groups saved")
        }
    }

    func restoreFromiCloud() async -> Bool {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()

        guard let jsonString = store.string(forKey: iCloudAlarmsKey),
              let jsonData = jsonString.data(using: .utf8),
              let iCloudData = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]],
              !iCloudData.isEmpty else {
            print("ℹ️ No iCloud alarm data found")
            return false
        }

        let existingAlarms = try? AlarmManager.shared.alarms
        if let existing = existingAlarms, !existing.isEmpty {
            print("ℹ️ Alarms already exist — skipping iCloud restore")
            return false
        }

        print("🔄 Restoring \(iCloudData.count) alarm groups from iCloud...")
        var restoredCount = 0

        for entry in iCloudData {
            guard
                let label         = entry["label"] as? String,
                let fireInterval  = entry["fireDate"] as? TimeInterval,
                let repeatDaysArr = entry["repeatDays"] as? [Int],
                let isEnabled     = entry["isEnabled"] as? Bool
            else { continue }

            let fireDate   = Date(timeIntervalSince1970: fireInterval)
            let repeatDays = Set(repeatDaysArr)
            let sound      = entry["sound"] as? String ?? "nokia.caf"
            let isVoice    = sound.hasPrefix("alarm_voice_")
            let finalSound = isVoice ? "nokia.caf" : sound

            if fireDate <= Date() && repeatDays.isEmpty {
                print("⏭ Skipping past alarm: \(label)")
                continue
            }

            _ = await scheduleFutureAlarm(
                date: fireDate,
                title: label,
                sound: finalSound,
                repeatDays: repeatDays
            )

            if !isEnabled {
                if let lastAlarm = alarms.last {
                    toggleAlarm(id: lastAlarm.id)
                }
            }

            restoredCount += 1
            print("✅ Restored alarm: \(label)")
        }

        print("✅ iCloud restore complete: \(restoredCount) alarms restored")
        return restoredCount > 0
    }

    // MARK: - Group persistence
    private func saveGroup(groupID: UUID, alarmIDs: [UUID], label: String, repeatDays: Set<Int>) {
        var groups = loadGroupIDs()
        groups[groupID.uuidString] = alarmIDs.map { $0.uuidString }
        UserDefaults.standard.set(groups, forKey: groupIDsKey)

        var labels = loadLabels()
        labels[groupID.uuidString] = label
        UserDefaults.standard.set(labels, forKey: labelsStoreKey)

        var repeatDict = loadGroupRepeatDays()
        repeatDict[groupID.uuidString] = Array(repeatDays)
        UserDefaults.standard.set(repeatDict, forKey: groupRepeatDaysKey)

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

    private func loadGroupIDs() -> [String: [String]] {
        UserDefaults.standard.dictionary(forKey: groupIDsKey) as? [String: [String]] ?? [:]
    }

    private func loadAlarmToGroup() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: alarmToGroupKey) as? [String: String] ?? [:]
    }

    private func loadGroupRepeatDays() -> [String: [Int]] {
        UserDefaults.standard.dictionary(forKey: groupRepeatDaysKey) as? [String: [Int]] ?? [:]
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
        alarms.removeAll { $0.alarm.id == alarm.id }
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
        }
    }
    // ✅ Save fired one-time alarm so it shows as disabled in list
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
            guard repeatDaysDict[groupIDStr]?.isEmpty ?? true else { continue }
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
}
