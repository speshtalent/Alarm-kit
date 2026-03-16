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
        alarms.removeAll { $0.alarm.id == id }
    }

    func loadAlarms() {
        do {
            let all = try AlarmManager.shared.alarms
            let labels = loadLabels()
            alarms = all
                .filter { $0.schedule != nil }
                .map { alarm in
                    AlarmListItem(alarm: alarm, label: labels[alarm.id.uuidString] ?? "Alarm")
                }
                .sorted { lhs, rhs in
                    (lhs.fireDate ?? .distantFuture) < (rhs.fireDate ?? .distantFuture)
                }
        } catch {
            print("Load alarms error:", error)
            alarms = []
        }
    }

    // ✅ UPDATED — generate UUID first, save voice file with that UUID,
    // then schedule alarm using that exact voice filename
    // this way each alarm has its own unique voice file — no sharing!
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

            // ✅ generate alarm ID first so we can name voice file after it
            let alarmID = UUID()
            var finalSound = sound

            if tempExists {
                // ✅ copy temp voice to alarm-specific file BEFORE scheduling
                let voiceFileName = "alarm_voice_\(alarmID.uuidString).caf"
                let destURL = libraryURL.appendingPathComponent("Sounds/\(voiceFileName)")
                try? FileManager.default.removeItem(at: destURL)
                try? FileManager.default.copyItem(at: tempURL, to: destURL)
                finalSound = voiceFileName
                print("✅ Voice file saved as: \(voiceFileName)")
            }
            // ✅ ADDED — mark that user has set at least one alarm
            UserDefaults.standard.set(true, forKey: "hasEverSetAlarm")

            // schedule alarm with the correct voice file as sound
            let id = try await scheduleAlarmWithID(id: alarmID, date: date, label: title, sound: finalSound)
            return id
        } catch {
            print("Schedule alarm error:", error)
            return nil
        }
    }

    // ✅ ADDED — schedule alarm with a pre-generated UUID
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
        alarms.append(AlarmListItem(alarm: alarm, label: label))
        alarms.sort { lhs, rhs in
            (lhs.fireDate ?? .distantFuture) < (rhs.fireDate ?? .distantFuture)
        }
    }
}
