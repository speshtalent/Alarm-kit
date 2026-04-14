import Foundation
import Combine
import AlarmKit
import SwiftUI
import AppIntents
import ActivityKit

@MainActor
final class TimerService: ObservableObject {

    static let shared = TimerService()

    @Published var timers: [Alarm] = []

    private init() {}

    private func makeAlert(for title: String) -> AlarmPresentation.Alert {
        let titleResource = LocalizedStringResource(stringLiteral: title)
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(
                title: titleResource,
                secondaryButton: AlarmButton(
                    text: "Repeat",
                    textColor: .white,
                    systemImageName: "repeat"
                ),
                secondaryButtonBehavior: .countdown
            )
        } else {
            return AlarmPresentation.Alert(
                title: titleResource,
                stopButton: AlarmButton(
                    text: "Stop",
                    textColor: .white,
                    systemImageName: "stop.fill"
                )
            )
        }
    }

    // MARK: - Load timers
    func loadTimers() {
        do {
            timers = try AlarmManager.shared.alarms.filter {
                $0.schedule == nil
            }
        } catch {
            print("Failed to load timers:", error)
        }
    }

    // MARK: - Start timer
    func startTimer(duration: TimeInterval, title: String, sound: String = "nokia.caf") async {
        do {
            let id = Alarm.ID()
            let alert = makeAlert(for: title)

            let countdown = AlarmPresentation.Countdown(
                title: LocalizedStringResource(stringLiteral: title),
                pauseButton: AlarmButton(
                    text: "Pause",
                    textColor: .orange,
                    systemImageName: "pause.fill"
                )
            )

            let paused = AlarmPresentation.Paused(
                title: LocalizedStringResource(stringLiteral: "Paused"),
                resumeButton: AlarmButton(
                    text: "Resume",
                    textColor: .orange,
                    systemImageName: "play.fill"
                )
            )

            let presentation = AlarmPresentation(
                alert: alert,
                countdown: countdown,
                paused: paused
            )

            let metadata = AppAlarmMetadata(title: title, icon: "timer")

            let attributes = AlarmAttributes(
                presentation: presentation,
                metadata: metadata,
                tintColor: .orange
            )

            let configuration = AlarmManager.AlarmConfiguration.timer(
                duration: duration,
                attributes: attributes,
                stopIntent: StopAlarmIntent(alarmID: id.uuidString),
                secondaryIntent: RepeatAlarmIntent(alarmID: id.uuidString),
                sound: .named(sound)
            )

            let timer = try await AlarmManager.shared.schedule(
                id: id,
                configuration: configuration
            )
            // ✅ Save timer duration so RepeatAlarmIntent can use it
            UserDefaults.standard.set(duration, forKey: "timerDuration_\(id.uuidString)")
            UserDefaults.standard.set(sound, forKey: "timerSound_\(id.uuidString)")
            // ✅ Also save to App Group so intent extension can read it
            let appGroup = UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")
            appGroup?.set(duration, forKey: "timerDuration_\(id.uuidString)")
            appGroup?.set(sound, forKey: "timerSound_\(id.uuidString)")

            timers.append(timer)
            print("⏱️ Timer started:", duration, "sound:", sound)

        } catch {
            print("❌ Failed to start timer:", error)
        }
    }

    // MARK: - Cancel timer
    func cancelTimer(id: Alarm.ID) {
        do {
            try AlarmManager.shared.cancel(id: id)
            timers.removeAll { $0.id == id }
            print("🗑️ Timer cancelled")
        } catch {
            timers.removeAll { $0.id == id }
            print("❌ Failed to cancel timer:", error)
        }
    }
}
