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
        let appGroup = UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")
        appGroup?.removeObject(forKey: "isSnoozed_\(alarmID)")
        await LiveActivityCoordinator.endSnoozeActivity(alarmID: alarmID)
        try AlarmManager.shared.cancel(id: id)

        if (appGroup?.double(forKey: "timerDuration_\(alarmID)") ?? 0) > 0 {
            let timerKeys = [
                "timerTitle_\(alarmID)",
                "timerDuration_\(alarmID)",
                "timerSound_\(alarmID)",
                "timerEndDate_\(alarmID)"
            ]
            for key in timerKeys {
                UserDefaults.standard.removeObject(forKey: key)
                appGroup?.removeObject(forKey: key)
            }
            await LiveActivityCoordinator.endTimerActivities()
            appGroup?.set(alarmID, forKey: "pendingTimerStop")
            appGroup?.synchronize()
            WidgetCenter.shared.reloadAllTimelines()
            return .result()
        }

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
            UserDefaults.standard.set(json, forKey: "AlarmHistory")
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

        let appGroup = UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")
        let timerDuration = appGroup?.double(forKey: "timerDuration_\(alarmID)") ?? 0
        let isTimer = timerDuration > 0
        let duration: TimeInterval
        if isTimer {
            duration = timerDuration
        } else {
            let globalSnoozeDuration = appGroup?.double(forKey: "globalSnoozeDuration") ?? 0
            let storedSnoozeDuration = appGroup?.double(forKey: "snoozeDuration_\(alarmID)") ?? UserDefaults.standard.double(forKey: "snoozeDuration_\(alarmID)")
            duration = globalSnoozeDuration > 0 ? globalSnoozeDuration * 60 : (storedSnoozeDuration > 0 ? storedSnoozeDuration : 300)
        }

        let labels = (appGroup?.dictionary(forKey: "AlarmLabelsByID") as? [String: String])
            ?? UserDefaults.standard.dictionary(forKey: "AlarmLabelsByID") as? [String: String]
            ?? [:]
        let label = isTimer
            ? (appGroup?.string(forKey: "timerTitle_\(alarmID)") ?? "Timer")
            : (labels[alarmID] ?? "Alarm")
        let fireDate = Date().addingTimeInterval(duration)

        do {
            try AlarmManager.shared.cancel(id: id)
        } catch {
            print("❌ Cancel error:", error)
        }

        let titleResource = LocalizedStringResource(stringLiteral: label)
        var scheduled: Alarm?
        if isTimer {
            await LiveActivityCoordinator.endTimerActivities()
            appGroup?.set(alarmID, forKey: "pendingTimerStop")
            appGroup?.synchronize()
            WidgetCenter.shared.reloadAllTimelines()
        } else {
            UserDefaults.standard.set(true, forKey: "isSnoozed_\(alarmID)")
            appGroup?.set(true, forKey: "isSnoozed_\(alarmID)")
            UserDefaults.standard.set(fireDate.timeIntervalSince1970, forKey: "disabledAlarmDate_\(alarmID)")
            var disabled = UserDefaults.standard.stringArray(forKey: "DisabledAlarmIDs") ?? []
            disabled.removeAll { $0 == alarmID }
            UserDefaults.standard.set(disabled, forKey: "DisabledAlarmIDs")

            await LiveActivityCoordinator.endAlarmActivities()
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
            let attributes: AlarmAttributes<AlarmLiveActivityMetadata> = AlarmAttributes(
                presentation: presentation,
                metadata: AlarmLiveActivityMetadata(title: label, icon: "alarm.fill"),
                tintColor: Color.orange
            )
            let soundName: String = {
                let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                let voicePath = libraryURL.appendingPathComponent("Sounds/alarm_voice_\(alarmID).caf").path
                if FileManager.default.fileExists(atPath: voicePath) {
                    return "alarm_voice_\(alarmID).caf"
                }
                let alarmToGroup = UserDefaults.standard.dictionary(forKey: "AlarmToGroupID") as? [String: String] ?? [:]
                let groupID = alarmToGroup[alarmID] ?? alarmID
                return UserDefaults.standard.string(forKey: "alarmSound_\(groupID)") ??
                    UserDefaults.standard.string(forKey: "alarmSound_\(alarmID)") ??
                    "nokia.caf"
            }()
            let configuration = AlarmManager.AlarmConfiguration(
                countdownDuration: nil,
                schedule: .fixed(fireDate),
                attributes: attributes,
                stopIntent: StopAlarmIntent(alarmID: alarmID),
                secondaryIntent: RepeatAlarmIntent(alarmID: alarmID),
                sound: .named(soundName)
            )
            scheduled = try? await AlarmManager.shared.schedule(id: id, configuration: configuration)
            await LiveActivityCoordinator.startSnoozeActivity(
                alarmID: alarmID,
                title: label,
                endDate: fireDate
            )
        }

        if let scheduled {
            print("✅ Repeat scheduled: \(String(describing: scheduled.schedule))")
            print("✅ Countdown duration: \(String(describing: scheduled.countdownDuration))")
        }

        return .result()
    }
}
