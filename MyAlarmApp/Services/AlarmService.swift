import Foundation
import Combine
import AlarmKit
import ActivityKit
import SwiftUI
import CoreData

@MainActor
final class AlarmService: ObservableObject {

    struct AlarmListItem: Identifiable {
        let alarm: Alarm
        let label: String
        let soundDescription: String

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
    private let soundChoiceStoreKey = "AlarmSoundChoiceByID"
    private let recordingPathStoreKey = "AlarmRecordingPathByID"

    private init() {}

    func requestAuthorizationIfNeeded() async {
        do {
            if AlarmManager.shared.authorizationState == .authorized { return }
            _ = try await AlarmManager.shared.requestAuthorization()
        } catch {
            print("Alarm authorization error: \(error)")
        }
    }

    @discardableResult
    func scheduleAlarm(
        date: Date,
        label: String,
        soundChoice: AlarmSoundChoice = .systemDefault
    ) async throws -> UUID {
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

        let sound: AlertConfiguration.AlertSound = resolvedSound(for: soundChoice)

        let configuration = AlarmManager.AlarmConfiguration(
            countdownDuration: nil,
            schedule: .fixed(scheduleDate),
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: id.uuidString),
            secondaryIntent: nil,
            sound: sound
        )

        let alarm = try await AlarmManager.shared.schedule(id: id, configuration: configuration)

        saveLabel(label, for: id)
        saveSoundChoice(soundChoice, for: id)
        if case let .customRecording(recordingID) = soundChoice {
            saveRecordingPathForAlarm(alarmID: id, recordingID: recordingID)
        }

        upsertAlarmInList(alarm, label: label)
        return id
    }

    func cancelAlarm(id: UUID) {
        do {
            try AlarmManager.shared.cancel(id: id)
        } catch {
            print("Cancel alarm error: \(error)")
        }

        removeLabel(for: id)
        removeSoundChoice(for: id)
        removeRecordingPath(for: id)
        alarms.removeAll { $0.alarm.id == id }
    }

    func loadAlarms() {
        do {
            let all = try AlarmManager.shared.alarms
            let labels = loadLabels()
            alarms = all
                .filter { $0.schedule != nil }
                .map { alarm in
                    let choice = soundChoice(for: alarm.id)
                    return AlarmListItem(
                        alarm: alarm,
                        label: labels[alarm.id.uuidString] ?? "Alarm",
                        soundDescription: soundDescription(for: choice)
                    )
                }
                .sorted { lhs, rhs in
                    (lhs.fireDate ?? .distantFuture) < (rhs.fireDate ?? .distantFuture)
                }
        } catch {
            print("Load alarms error: \(error)")
            alarms = []
        }
    }

    func scheduleFutureAlarm(
        date: Date,
        title: String,
        snoozeEnabled: Bool = true,
        snoozeDuration: TimeInterval = 300,
        soundChoice: AlarmSoundChoice = .systemDefault
    ) async {
        do {
            _ = try await scheduleAlarm(date: date, label: title, soundChoice: soundChoice)
        } catch {
            print("Schedule alarm error: \(error)")
        }
    }

    func recordingURL(for alarmID: UUID) -> URL? {
        let map = loadRecordingPaths()
        guard let relativePath = map[alarmID.uuidString] else { return nil }
        let url = VoiceRecordingStorage.recordingsDirectory.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func soundChoice(for alarmID: UUID) -> AlarmSoundChoice {
        loadSoundChoices()[alarmID.uuidString] ?? .systemDefault
    }

    private func resolvedSound(for soundChoice: AlarmSoundChoice) -> AlertConfiguration.AlertSound {
        switch soundChoice {
        case .systemDefault:
            return .named("nokia.caf")
        case let .customRecording(recordingID):
            if let copiedName = copyRecordingToAlarmSoundLocation(recordingID: recordingID) {
                return .named(copiedName)
            }
            return .named("nokia.caf")
        }
    }

    private func soundDescription(for soundChoice: AlarmSoundChoice) -> String {
        switch soundChoice {
        case .systemDefault:
            return "System: Nokia"
        case let .customRecording(recordingID):
            guard let recording = fetchRecording(id: recordingID) else {
                return "Custom recording"
            }
            return "Custom: \(recording.name)"
        }
    }

    private func fetchRecording(id: UUID) -> VoiceRecording? {
        let context = PersistenceController.shared.container.viewContext
        let request = VoiceRecording.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }

    private func copyRecordingToAlarmSoundLocation(recordingID: UUID) -> String? {
        guard let recording = fetchRecording(id: recordingID) else { return nil }
        let inputURL = recording.fileURL
        guard FileManager.default.fileExists(atPath: inputURL.path) else { return nil }

        let soundsDir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: soundsDir, withIntermediateDirectories: true)

        let ext = inputURL.pathExtension.isEmpty ? "m4a" : inputURL.pathExtension
        let fileName = "alarm-\(recordingID.uuidString).\(ext)"
        let outputURL = soundsDir.appendingPathComponent(fileName)

        do {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.copyItem(at: inputURL, to: outputURL)
            return fileName
        } catch {
            print("Failed to copy recording to alarm sound location: \(error)")
            return nil
        }
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

    private func loadSoundChoices() -> [String: AlarmSoundChoice] {
        guard
            let data = UserDefaults.standard.data(forKey: soundChoiceStoreKey),
            let decoded = try? JSONDecoder().decode([String: AlarmSoundChoice].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private func saveSoundChoice(_ soundChoice: AlarmSoundChoice, for id: UUID) {
        var all = loadSoundChoices()
        all[id.uuidString] = soundChoice
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: soundChoiceStoreKey)
        }
    }

    private func removeSoundChoice(for id: UUID) {
        var all = loadSoundChoices()
        all.removeValue(forKey: id.uuidString)
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: soundChoiceStoreKey)
        }
    }

    private func loadRecordingPaths() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: recordingPathStoreKey) as? [String: String] ?? [:]
    }

    private func saveRecordingPathForAlarm(alarmID: UUID, recordingID: UUID) {
        guard let recording = fetchRecording(id: recordingID) else { return }
        var map = loadRecordingPaths()
        map[alarmID.uuidString] = recording.relativePath
        UserDefaults.standard.set(map, forKey: recordingPathStoreKey)
    }

    private func removeRecordingPath(for alarmID: UUID) {
        var map = loadRecordingPaths()
        map.removeValue(forKey: alarmID.uuidString)
        UserDefaults.standard.set(map, forKey: recordingPathStoreKey)
    }

    private func upsertAlarmInList(_ alarm: Alarm, label: String) {
        alarms.removeAll { $0.alarm.id == alarm.id }
        alarms.append(AlarmListItem(
            alarm: alarm,
            label: label,
            soundDescription: soundDescription(for: soundChoice(for: alarm.id))
        ))
        alarms.sort { lhs, rhs in
            (lhs.fireDate ?? .distantFuture) < (rhs.fireDate ?? .distantFuture)
        }
    }
}
