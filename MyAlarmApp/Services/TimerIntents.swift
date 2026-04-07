import AppIntents
import AlarmKit
import SwiftUI
import ActivityKit

struct StopAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop"

    @Parameter(title: "alarmID")
    var alarmID: String

    init(alarmID: String) { self.alarmID = alarmID }
    init() { self.alarmID = "" }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        try AlarmManager.shared.cancel(id: id)
        UserDefaults.standard.set(alarmID, forKey: "lastFiredAlarmID")
        UserDefaults.standard.set(true, forKey: "pendingVoicePlay")
        NotificationCenter.default.post(name: NSNotification.Name("AlarmDidStop"), object: nil)
        let savedLabels = UserDefaults.standard.dictionary(forKey: "AlarmLabelsByID") as? [String: String] ?? [:]
        let alarmLabel = savedLabels[alarmID] ?? "Alarm"
        var history = (UserDefaults.standard.string(forKey: "AlarmHistory")
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] }) ?? []
        let entry: [String: Any] = ["alarmID": alarmID, "label": alarmLabel, "firedAt": Date().timeIntervalSince1970]
        history.insert(entry, at: 0)
        if history.count > 50 { history = Array(history.prefix(50)) }
        if let data = try? JSONSerialization.data(withJSONObject: history),
           let json = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(json, forKey: "AlarmHistory")
        }
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
