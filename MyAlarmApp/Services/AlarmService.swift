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

    // MARK: - Public API
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
        // find the alarm's fireDate BEFORE removing from list
        // use fireDate as key — same key used when adding to calendar in AddAlarmView
        if let item = alarms.first(where: { $0.id == id }),
           let fireDate = item.fireDate {
            let key = fireDate.timeIntervalSince1970.description
            CalendarService.shared.removeAlarmFromCalendar(alarmID: key)
            print("✅ Removing calendar event for key: \(key)")
        }
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
                    AlarmListItem(
                        alarm: alarm,
                        label: labels[alarm.id.uuidString] ?? "Alarm"
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

    // ✅ Updated with sound parameter
    func scheduleFutureAlarm(
        date: Date,
        title: String,
        snoozeEnabled: Bool = true,
        snoozeDuration: TimeInterval = 300,
        sound: String = "nokia.caf"
    ) async {
        do {
            // Check if voice recording exists — use it as alarm sound
            let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            let voiceURL = libraryURL.appendingPathComponent("Sounds/alarm_voice.caf")
            let finalSound = FileManager.default.fileExists(atPath: voiceURL.path) ? "alarm_voice.caf" : sound
            
            _ = try await scheduleAlarm(date: date, label: title, sound: finalSound)
        } catch {
            print("Schedule alarm error:", error)
        }
    }

    // MARK: - Local label persistence
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
