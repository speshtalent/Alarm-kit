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

        var repeatLabel: String {
            if repeatDays.isEmpty { return "" }
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

    // ✅ iCloud KV store key
    private let iCloudAlarmsKey = "iCloudSavedAlarms"

    private init() {}

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
        let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: label))
        let presentation = AlarmPresentation(alert: alert)
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: AppAlarmMetadata(title: label, icon: "alarm"),
            tintColor: .orange
        )
        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: nil,
            schedule: .fixed(scheduleDate),
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: id.uuidString),
            secondaryIntent: nil,
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

        removeGroup(groupID: groupID)
        rebuildGroups()
        saveNextAlarmForWidget()
        // ✅ Sync to iCloud after cancel
        syncToiCloud()
    }

    func toggleAlarm(id: UUID) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        let item = alarms[index]

        if item.isEnabled {
            do {
                try AlarmManager.shared.cancel(id: id)
                alarms[index] = AlarmListItem(alarm: item.alarm, label: item.label, isEnabled: false)
                saveDisabledState(id: id, disabled: true)
                print("⏸ Alarm disabled: \(id)")
            } catch {
                print("Disable alarm error:", error)
            }
            saveNextAlarmForWidget()
        } else {
            guard let fireDate = item.fireDate, fireDate > Date() else {
                print("⚠️ Cannot re-enable past alarm")
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
            alarms = all
                .filter { $0.schedule != nil }
                .map { alarm in
                    AlarmListItem(
                        alarm: alarm,
                        label: labels[alarm.id.uuidString] ?? "Alarm",
                        isEnabled: !disabled.contains(alarm.id.uuidString)
                    )
                }
                .sorted { lhs, rhs in
                    (lhs.fireDate ?? .distantFuture) < (rhs.fireDate ?? .distantFuture)
                }
        } catch {
            print("Load alarms error:", error)
            alarms = []
        }
        rebuildGroups()
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
        repeatDays: Set<Int> = []
    ) async -> UUID? {
        do {
            let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            let tempURL = libraryURL.appendingPathComponent("Sounds/alarm_voice_temp.caf")
            let tempExists = FileManager.default.fileExists(atPath: tempURL.path)

            let alarmID = UUID()
            var finalSound = sound

            if tempExists && repeatDays.isEmpty {
                let voiceFileName = "alarm_voice_\(alarmID.uuidString).caf"
                let destURL = libraryURL.appendingPathComponent("Sounds/\(voiceFileName)")
                try? FileManager.default.removeItem(at: destURL)
                try? FileManager.default.copyItem(at: tempURL, to: destURL)
                finalSound = voiceFileName
                print("✅ Voice file saved as: \(voiceFileName)")
            }
            UserDefaults.standard.set(true, forKey: "hasEverSetAlarm")

            if repeatDays.isEmpty {
                let id = try await scheduleAlarmWithID(id: alarmID, date: date, label: title, sound: finalSound)
                saveGroup(groupID: id, alarmIDs: [id], label: title, repeatDays: [])
                rebuildGroups()
                saveNextAlarmForWidget()
                // ✅ Sync to iCloud after scheduling
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
                // ✅ Sync to iCloud after scheduling
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
        let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: label))
        let presentation = AlarmPresentation(alert: alert)
        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: AppAlarmMetadata(title: label, icon: "alarm"),
            tintColor: .orange
        )
        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: nil,
            schedule: .fixed(scheduleDate),
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: id.uuidString),
            secondaryIntent: nil,
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
        let nextAlarm = alarms
            .filter { $0.isEnabled }
            .compactMap { item -> (Date, String)? in
                guard let fireDate = item.fireDate, fireDate > Date() else { return nil }
                return (fireDate, item.label)
            }
            .sorted { $0.0 < $1.0 }
            .first

        if let (fireDate, label) = nextAlarm {
            userDefaults?.set(fireDate.timeIntervalSince1970, forKey: "widgetNextAlarmDate")
            userDefaults?.set(label, forKey: "widgetNextAlarmLabel")
            userDefaults?.synchronize()
            print("✅ Widget saved: \(label) at \(fireDate)")
        } else {
            userDefaults?.removeObject(forKey: "widgetNextAlarmDate")
            userDefaults?.removeObject(forKey: "widgetNextAlarmLabel")
            userDefaults?.synchronize()
            print("✅ Widget cleared — no active alarms")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - ✅ iCloud Sync

    // Save all current alarm groups to iCloud KV store
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
                "sound":      "nokia.caf"  // default — voice not backed up
            ]
            // Get sound from first alarm label
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

    // ✅ Restore alarms from iCloud — returns true if alarms were restored
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

        // Check if AlarmKit already has alarms (not a fresh install)
        let existingAlarms = try? AlarmManager.shared.alarms
        if let existing = existingAlarms, !existing.isEmpty {
            print("ℹ️ Alarms already exist — skipping iCloud restore")
            return false
        }

        print("🔄 Restoring \(iCloudData.count) alarm groups from iCloud...")
        var restoredCount = 0

        for entry in iCloudData {
            guard
                let label        = entry["label"] as? String,
                let fireInterval = entry["fireDate"] as? TimeInterval,
                let repeatDaysArr = entry["repeatDays"] as? [Int],
                let isEnabled    = entry["isEnabled"] as? Bool
            else { continue }

            let fireDate   = Date(timeIntervalSince1970: fireInterval)
            let repeatDays = Set(repeatDaysArr)
            let sound      = entry["sound"] as? String ?? "nokia.caf"

            // Skip if voice recording — restore with default sound instead
            let isVoice   = sound.hasPrefix("alarm_voice_")
            let finalSound = isVoice ? "nokia.caf" : sound

            // Skip past alarms that have no repeat days
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
                // Toggle off if it was disabled
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
}
