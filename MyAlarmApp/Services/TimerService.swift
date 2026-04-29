import Foundation
import Combine
import AlarmKit
import SwiftUI
import AppIntents
import ActivityKit

struct TimerViewModel: Identifiable, Equatable, Hashable {
    enum State {
        case running
        case paused
        case idle
    }

    let id: UUID
    let title: String
    let state: State
    let totalDuration: TimeInterval
    let remainingDuration: TimeInterval
    let sound: String
    let endDate: Date?

    var displayDurationText: String {
        formatDuration(totalDuration)
    }

    var statusText: String {
        switch state {
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        case .idle:
            return "Idle"
        }
    }

    var fallbackRemainingText: String {
        formatDuration(remainingDuration)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let total = max(Int(duration.rounded()), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours) hr" }
        if minutes > 0 && seconds > 0 { return "\(minutes)m \(seconds)s" }
        if minutes > 0 { return "\(minutes) min" }
        return "\(seconds) sec"
    }
}

@MainActor
final class TimerService: ObservableObject {

    static let shared = TimerService()

    @Published var timers: [Alarm] = []
    @Published var timerViewModels: [TimerViewModel] = []

    private init() {}

    private func titleKey(for id: UUID) -> String { "timerTitle_\(id.uuidString)" }
    private func durationKey(for id: UUID) -> String { "timerDuration_\(id.uuidString)" }
    private func soundKey(for id: UUID) -> String { "timerSound_\(id.uuidString)" }
    private func endDateKey(for id: UUID) -> String { "timerEndDate_\(id.uuidString)" }

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
            timerViewModels = timers.map(makeViewModel).sorted { $0.title < $1.title }
            removeMetadataForInactiveTimers()
        } catch {
            print("Failed to load timers:", error)
            timerViewModels = []
        }
    }

    // MARK: - Start timer
    func startTimer(duration: TimeInterval, title: String, sound: String = "nokia.caf") async {
        do {
            let id = Alarm.ID()
            await LiveActivityCoordinator.endTimerActivities()
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

            let endDate = Date().addingTimeInterval(duration)
            let attributes: AlarmAttributes<TimerLiveActivityMetadata> = AlarmAttributes(
                presentation: presentation,
                metadata: TimerLiveActivityMetadata(title: title, icon: "timer"),
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
            UserDefaults.standard.set(title, forKey: titleKey(for: id))
            UserDefaults.standard.set(sound, forKey: "timerSound_\(id.uuidString)")
            UserDefaults.standard.set(endDate.timeIntervalSince1970, forKey: endDateKey(for: id))
            // ✅ Also save to App Group so intent extension can read it
            let appGroup = UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")
            appGroup?.set(duration, forKey: "timerDuration_\(id.uuidString)")
            appGroup?.set(sound, forKey: "timerSound_\(id.uuidString)")
            appGroup?.set(title, forKey: titleKey(for: id))
            appGroup?.set(endDate.timeIntervalSince1970, forKey: endDateKey(for: id))

            timers.append(timer)
            timerViewModels = timers.map(makeViewModel).sorted { $0.title < $1.title }
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
            removeMetadata(for: id)
            timerViewModels = timers.map(makeViewModel).sorted { $0.title < $1.title }
            Task { await LiveActivityCoordinator.endTimerActivities() }
            print("🗑️ Timer cancelled")
        } catch {
            timers.removeAll { $0.id == id }
            removeMetadata(for: id)
            timerViewModels = timers.map(makeViewModel).sorted { $0.title < $1.title }
            Task { await LiveActivityCoordinator.endTimerActivities() }
            print("❌ Failed to cancel timer:", error)
        }
    }

    func viewModel(for id: UUID) -> TimerViewModel? {
        timerViewModels.first(where: { $0.id == id })
    }

    private func makeViewModel(for timer: Alarm) -> TimerViewModel {
        let storedTitle = UserDefaults.standard.string(forKey: titleKey(for: timer.id)) ?? "Timer"
        let storedDuration = UserDefaults.standard.double(forKey: durationKey(for: timer.id))
        let storedSound = UserDefaults.standard.string(forKey: soundKey(for: timer.id)) ?? "nokia.caf"
        let storedEndDate = UserDefaults.standard.object(forKey: endDateKey(for: timer.id)) as? TimeInterval
        let endDate = storedEndDate.map(Date.init(timeIntervalSince1970:))
        let countdown = timer.countdownDuration

        // WHY: AlarmKit already tells us whether there is active or paused countdown data,
        // so the row should render from that single derived state instead of duplicating rules in the view.
        let state: TimerViewModel.State
        let remaining: TimeInterval
        if let runningRemaining = countdown?.preAlert, runningRemaining > 0 {
            state = .running
            remaining = runningRemaining
        } else if let pausedRemaining = countdown?.postAlert, pausedRemaining > 0 {
            state = .paused
            remaining = pausedRemaining
        } else {
            state = .idle
            remaining = max(storedDuration, 0)
        }

        return TimerViewModel(
            id: timer.id,
            title: storedTitle,
            state: state,
            totalDuration: max(storedDuration, remaining),
            remainingDuration: remaining,
            sound: storedSound,
            endDate: state == .running ? (endDate ?? Date().addingTimeInterval(remaining)) : nil
        )
    }

    private func removeMetadata(for id: UUID) {
        let keys = [
            titleKey(for: id),
            durationKey(for: id),
            soundKey(for: id),
            endDateKey(for: id)
        ]
        let appGroup = UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
            appGroup?.removeObject(forKey: key)
        }
    }

    private func removeMetadataForInactiveTimers() {
        let activeIDs = Set(timers.map(\.id.uuidString))
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in keys where key.hasPrefix("timerDuration_") {
            let id = key.replacingOccurrences(of: "timerDuration_", with: "")
            guard !activeIDs.contains(id), let uuid = UUID(uuidString: id) else { continue }
            removeMetadata(for: uuid)
        }
    }
}
