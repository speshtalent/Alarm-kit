import AppIntents
import AlarmKit
import SwiftUI
import ActivityKit
import WidgetKit

struct StopAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop"

    @Parameter(title: "alarmID")
    var alarmID: String

    init(alarmID: String) { self.alarmID = alarmID }
    init() { self.alarmID = "" }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        try AlarmManager.shared.cancel(id: id)

        // ✅ Use App Group — shared between extension and main app
        let appGroup = UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")

        appGroup?.set(alarmID, forKey: "lastFiredAlarmID")
        appGroup?.set(true, forKey: "pendingVoicePlay")

        // ✅ Read labels from App Group
        let savedLabels = appGroup?.dictionary(forKey: "AlarmLabelsByID") as? [String: String] ?? [:]
        let alarmLabel = savedLabels[alarmID] ?? "Alarm"

        // ✅ Save history to App Group
        var history: [[String: Any]] = []
        if let json = appGroup?.string(forKey: "AlarmHistory"),
           let data = json.data(using: .utf8),
           let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            history = list
        }
        let entry: [String: Any] = [
            "alarmID": alarmID,
            "label": alarmLabel,
            "firedAt": Date().timeIntervalSince1970
        ]
        history.insert(entry, at: 0)
        if history.count > 50 { history = Array(history.prefix(50)) }
        if let data = try? JSONSerialization.data(withJSONObject: history),
           let json = String(data: data, encoding: .utf8) {
            appGroup?.set(json, forKey: "AlarmHistory")
        }

        // ✅ Save fired one-time alarm to UserDefaults
        let repeatDaysDict = UserDefaults.standard.dictionary(forKey: "GroupRepeatDays") as? [String: [Int]] ?? [:]
        let alarmToGroup = UserDefaults.standard.dictionary(forKey: "AlarmToGroupID") as? [String: String] ?? [:]
        let groupIDStr = alarmToGroup[alarmID]
        let repeatDays = groupIDStr.flatMap { repeatDaysDict[$0] } ?? []

        if repeatDays.isEmpty {
            var firedAlarms = (appGroup?.string(forKey: "FiredOneTimeAlarms")
                .flatMap { $0.data(using: .utf8) }
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: [String: Any]] }) ?? [:]
            firedAlarms[alarmID] = [
                "label": alarmLabel,
                "firedAt": Date().timeIntervalSince1970
            ]
            if let data = try? JSONSerialization.data(withJSONObject: firedAlarms),
               let json = String(data: data, encoding: .utf8) {
                appGroup?.set(json, forKey: "FiredOneTimeAlarms")
            }
        }

        // ✅ Remove fired alarm from upcoming list
        if let json = appGroup?.string(forKey: "widgetUpcomingAlarms"),
           let data = json.data(using: .utf8),
           var list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            list.removeAll { item in
                guard let ts = item["date"] as? TimeInterval else { return false }
                let date = Date(timeIntervalSince1970: ts)
                return date <= Date()
            }
            if let newData = try? JSONSerialization.data(withJSONObject: list),
               let newJson = String(data: newData, encoding: .utf8) {
                appGroup?.set(newJson, forKey: "widgetUpcomingAlarms")
            }
        }

        // ✅ Clear next alarm so widget refreshes to next one
        appGroup?.removeObject(forKey: "widgetNextAlarmDate")
        appGroup?.removeObject(forKey: "widgetNextAlarmLabel")
        appGroup?.synchronize()

        // ✅ Reload widget
        WidgetCenter.shared.reloadAllTimelines()

        return .result()
    }
}

struct RepeatAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Repeat"

    @Parameter(title: "alarmID")
    var alarmID: String

    init(alarmID: String) { self.alarmID = alarmID }
    init() { self.alarmID = "" }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }

        // ✅ Get snooze duration from UserDefaults
        let snoozeDuration = UserDefaults.standard.double(forKey: "snoozeDuration_\(alarmID)")
        let duration = snoozeDuration > 0 ? snoozeDuration : 300

        // ✅ Get alarm label
        let labels = UserDefaults.standard.dictionary(forKey: "AlarmLabelsByID") as? [String: String] ?? [:]
        let label = labels[alarmID] ?? "Alarm"

        // ✅ Schedule new alarm after snooze duration
        let snoozeDate = Date().addingTimeInterval(duration)

        do {
            try AlarmManager.shared.cancel(id: id)
        } catch {
            print("❌ Cancel error:", error)
        }

        Task {
            let titleResource = LocalizedStringResource(stringLiteral: label)
            let alert: AlarmPresentation.Alert
            if #available(iOS 26.1, *) {
                alert = AlarmPresentation.Alert(
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
                alert = AlarmPresentation.Alert(
                    title: titleResource,
                    stopButton: AlarmButton(
                        text: "Stop Alarm",
                        textColor: .white,
                        systemImageName: "alarm.fill"
                    )
                )
            }
            let presentation = AlarmPresentation(alert: alert)
            let attributes = AlarmAttributes(
                presentation: presentation,
                metadata: AppAlarmMetadata(title: label, icon: "alarm"),
                tintColor: Color.orange
            )
            let configuration = AlarmManager.AlarmConfiguration(
                countdownDuration: nil,
                schedule: .fixed(snoozeDate),
                attributes: attributes,
                stopIntent: StopAlarmIntent(alarmID: alarmID),
                secondaryIntent: RepeatAlarmIntent(alarmID: alarmID),
                sound: {
                    let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                    let voicePath = libraryURL.appendingPathComponent("Sounds/alarm_voice_\(alarmID).caf").path
                    let soundFile = FileManager.default.fileExists(atPath: voicePath) ? "alarm_voice_\(alarmID).caf" : "nokia.caf"
                    return .named(soundFile)
                }()
            )
            _ = try? await AlarmManager.shared.schedule(id: id, configuration: configuration)
        }

        return .result()
    }
}
