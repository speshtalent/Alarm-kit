import Foundation
import Combine
import AlarmKit
import ActivityKit
import SwiftUI
import AppIntents

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

    static let shared = AlarmService()

    @Published var alarms: [AlarmListItem] = []

    private let labelsStoreKey = "AlarmLabelsByID"
    private let disabledAlarmsKey = "DisabledAlarmIDs"

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

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: label)
        )
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
        if let item = alarms.first(where: { $0.id == id }),
           let fireDate = item.fireDate {
            let key = fireDate.timeIntervalSince1970.description
            CalendarService.shared.removeAlarmFromCalendar(alarmID: key)
            print("✅ Removing calendar event for key: \(key)")
        }
        deleteVoiceFile(for: id.uuidString)
        do {
            try AlarmManager.shared.cancel(id: id)
        } catch {
            print("Cancel alarm error:", error)
        }
        removeLabel(for: id)
        removeFromDisabled(id: id)
        alarms.removeAll { $0.alarm.id == id }
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
            }
        }
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
    }

    func scheduleFutureAlarm(
        date: Date,
        title: String,
        snoozeEnabled: Bool = true,
        snoozeDuration: TimeInterval = 300,
        sound: String = "nokia.caf"
    ) async -> UUID? {
        do {
            let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            let tempURL = libraryURL.appendingPathComponent("Sounds/alarm_voice_temp.caf")
            let tempExists = FileManager.default.fileExists(atPath: tempURL.path)

            let alarmID = UUID()
            var finalSound = sound

            if tempExists {
                let voiceFileName = "alarm_voice_\(alarmID.uuidString).caf"
                let destURL = libraryURL.appendingPathComponent("Sounds/\(voiceFileName)")
                try? FileManager.default.removeItem(at: destURL)
                try? FileManager.default.copyItem(at: tempURL, to: destURL)
                finalSound = voiceFileName
                print("✅ Voice file saved as: \(voiceFileName)")
            }
            UserDefaults.standard.set(true, forKey: "hasEverSetAlarm")

            let id = try await scheduleAlarmWithID(id: alarmID, date: date, label: title, sound: finalSound)
            return id
        } catch {
            print("Schedule alarm error:", error)
            return nil
        }
    }

    @discardableResult
    func scheduleAlarmWithID(id: UUID, date: Date, label: String, sound: String = "nokia.caf") async throws -> UUID {
        let scheduleDate = max(date, Date().addingTimeInterval(1))

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: label)
        )
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

    private func loadDisabledIDs() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: disabledAlarmsKey) ?? []
        return Set(array)
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
