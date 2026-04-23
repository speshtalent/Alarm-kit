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
        // ✅ Clear snooze flag
        UserDefaults.standard.removeObject(forKey: "isSnoozed_\(alarmID)")
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
        // ✅ Use original timer duration first, then snooze duration, then default
        let appGroup = UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")
        let timerDuration = appGroup?.double(forKey: "timerDuration_\(alarmID)") ?? 0
        // ✅ Always use global snooze setting for alarms
        let globalSnoozeDuration = appGroup?.double(forKey: "globalSnoozeDuration") ?? 0
        let snoozeDuration = UserDefaults.standard.double(forKey: "snoozeDuration_\(alarmID)")
        let duration = timerDuration > 0 ? timerDuration : (globalSnoozeDuration > 0 ? globalSnoozeDuration * 60 : (snoozeDuration > 0 ? snoozeDuration : 300))

        // ✅ Get alarm label
        let isTimer = (appGroup?.double(forKey: "timerDuration_\(alarmID)") ?? 0) > 0
        let labels = UserDefaults.standard.dictionary(forKey: "AlarmLabelsByID") as? [String: String] ?? [:]
        let label = labels[alarmID] ?? (isTimer ? "Timer" : "Alarm")

        // ✅ Schedule new alarm after snooze duration
        //let snoozeDate = Date().addingTimeInterval(duration)

        do {
            try AlarmManager.shared.cancel(id: id)
            // ✅ Mark as snoozed
            UserDefaults.standard.set(true, forKey: "isSnoozed_\(alarmID)")
            appGroup?.set(true, forKey: "isSnoozed_\(alarmID)")
            // ✅ Save snooze fire date so UI can show it
            let snoozeFireDate = Date().addingTimeInterval(duration)
            UserDefaults.standard.set(snoozeFireDate.timeIntervalSince1970, forKey: "disabledAlarmDate_\(alarmID)")
            // ✅ Remove from disabled list
            var disabled = UserDefaults.standard.stringArray(forKey: "DisabledAlarmIDs") ?? []
            disabled.removeAll { $0 == alarmID }
            UserDefaults.standard.set(disabled, forKey: "DisabledAlarmIDs")
        } catch {
            print("❌ Cancel error:", error)
        }

        Task {
            let titleResource = LocalizedStringResource(stringLiteral: label)
            let alert: AlarmPresentation.Alert
            if isTimer {
                if #available(iOS 26.1, *) {
                    alert = AlarmPresentation.Alert(
                        title: titleResource,
                        secondaryButton: AlarmButton(
                            text: "Repeat",
                            textColor: .white,
                            systemImageName: "repeat"
                        ),
                        secondaryButtonBehavior: .countdown
                    )
                } else {
                    alert = AlarmPresentation.Alert(
                        title: titleResource,
                        stopButton: AlarmButton(
                            text: "Stop",
                            textColor: .white,
                            systemImageName: "stop.fill"
                        )
                    )
                }
            } else {
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
            }
            let presentation = AlarmPresentation(
                alert: alert,
                countdown: AlarmPresentation.Countdown(
                    title: LocalizedStringResource(stringLiteral: label)
                )
            )
            let attributes = AlarmAttributes(
                presentation: presentation,
                metadata: AppAlarmMetadata(title: label, icon: isTimer ? "timer" : "alarm"),
                tintColor: Color.orange
            )
            let configuration = AlarmManager.AlarmConfiguration.timer(
                duration: duration,
                attributes: attributes,
                stopIntent: StopAlarmIntent(alarmID: alarmID),
                secondaryIntent: RepeatAlarmIntent(alarmID: alarmID),
                sound: {
                    let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                    // ✅ Check custom voice file first
                    let voicePath = libraryURL.appendingPathComponent("Sounds/alarm_voice_\(alarmID).caf").path
                    if FileManager.default.fileExists(atPath: voicePath) {
                        return .named("alarm_voice_\(alarmID).caf")
                    }
                    // ✅ Check saved ringtone for this alarm
                    let alarmToGroup = UserDefaults.standard.dictionary(forKey: "AlarmToGroupID") as? [String: String] ?? [:]
                    let groupID = alarmToGroup[alarmID] ?? alarmID
                    let savedSound = UserDefaults.standard.string(forKey: "alarmSound_\(groupID)") ??
                                     UserDefaults.standard.string(forKey: "alarmSound_\(alarmID)") ?? "nokia.caf"
                    return .named(savedSound)
                }()
            )
            if let scheduled = try? await AlarmManager.shared.schedule(id: id, configuration: configuration) {
                print("✅ Snooze scheduled: \(String(describing: scheduled.schedule))")
                print("✅ Countdown duration: \(String(describing: scheduled.countdownDuration))")
            }
        }

        return .result()
    }
}
