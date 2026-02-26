import Foundation
import Combine
import AlarmKit
import ActivityKit
import SwiftUI
import AppIntents

@MainActor
final class AlarmService: ObservableObject {

    static let shared = AlarmService()

    @Published var alarms: [Alarm] = []

    private init() {}

    // MARK: - Load existing alarms
    func loadAlarms() {
        do {
            let all = try AlarmManager.shared.alarms
            print("📋 All alarms count:", all.count)
            for a in all {
                print("   - id:", a.id)
                print("   - schedule:", String(describing: a.schedule))
                print("   - state:", String(describing: a.state))
            }
            alarms = all.filter { $0.schedule != nil }
            print("📋 Filtered alarms:", alarms.count)
        } catch {
            print("❌ loadAlarms error:", error)
        }
    }

    // MARK: - Schedule alarm
    func scheduleFutureAlarm(date: Date, title: String, snoozeEnabled: Bool = true, snoozeDuration: TimeInterval = 300) async {
        print("🚨 scheduleFutureAlarm called!")

        // ✅ Always ensure date is in the future
        let scheduleDate = date < Date() ? Date().addingTimeInterval(60) : date
        print("📅 Final schedule date:", scheduleDate)
        print("📅 Title:", title)
        print("📅 Snooze:", snoozeEnabled)

        do {
            let id = Alarm.ID()

            let schedule = Alarm.Schedule.fixed(scheduleDate)
            print("⏰ Fixed schedule set for:", scheduleDate)

            let alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                secondaryButton: snoozeEnabled ? AlarmButton(
                    text: "Snooze",
                    textColor: .white,
                    systemImageName: "moon.zzz.fill"
                ) : nil,
                secondaryButtonBehavior: snoozeEnabled ? .countdown : nil
            )

            let presentation: AlarmPresentation
            if snoozeEnabled {
                presentation = AlarmPresentation(
                    alert: alert,
                    countdown: AlarmPresentation.Countdown(
                        title: "Snoozed",
                        pauseButton: AlarmButton(
                            text: "Pause",
                            textColor: .orange,
                            systemImageName: "pause.fill"
                        )
                    ),
                    paused: AlarmPresentation.Paused(
                        title: "Paused",
                        resumeButton: AlarmButton(
                            text: "Resume",
                            textColor: .orange,
                            systemImageName: "play.fill"
                        )
                    )
                )
            } else {
                presentation = AlarmPresentation(alert: alert)
            }

            let attributes = AlarmAttributes(
                presentation: presentation,
                metadata: AppAlarmMetadata(title: title, icon: "alarm"),
                tintColor: .orange
            )

            let configuration = AlarmManager.AlarmConfiguration(
                countdownDuration: snoozeEnabled ? Alarm.CountdownDuration(preAlert: nil, postAlert: snoozeDuration) : nil,
                schedule: schedule,
                attributes: attributes,
                stopIntent: StopAlarmIntent(alarmID: id.uuidString),
                secondaryIntent: snoozeEnabled ? RepeatAlarmIntent(alarmID: id.uuidString) : nil,
                sound: .named("")
            )

            print("⚙️ Configuration created, scheduling now...")

            let alarm = try await AlarmManager.shared.schedule(
                id: id,
                configuration: configuration
            )

            alarms.append(alarm)
            print("✅ Alarm scheduled! Total:", alarms.count)

        } catch {
            print("❌ Schedule failed:", error)
            print("❌ Details:", error.localizedDescription)
        }
    }

    // MARK: - Cancel alarm
    func cancelAlarm(id: Alarm.ID) {
        do {
            try AlarmManager.shared.cancel(id: id)
            alarms.removeAll { $0.id == id }
            print("🗑️ Alarm cancelled")
        } catch {
            alarms.removeAll { $0.id == id }
            print("❌ Cancel error:", error)
        }
    }
}
