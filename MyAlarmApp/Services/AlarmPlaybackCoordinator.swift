import Foundation
import AlarmKit

@MainActor
final class AlarmPlaybackCoordinator {
    static let shared = AlarmPlaybackCoordinator()

    private let audioManager: AudioManaging
    private var updatesTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var activeAlarmID: UUID?
    private var activeRecordingURL: URL?

    init() {
        self.audioManager = AudioManager.shared
    }

    init(audioManager: AudioManaging) {
        self.audioManager = audioManager
    }

    func start() {
        guard updatesTask == nil else { return }

        updatesTask = Task {
            for await alarms in AlarmManager.shared.alarmUpdates {
                for alarm in alarms {
                    await self.handle(alarm: alarm)
                }
                await self.stopPlaybackIfActiveAlarmDisappeared(alarms: alarms)
            }
        }

        pollTask = Task {
            while !Task.isCancelled {
                await self.scanAllAlarms()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil

        pollTask?.cancel()
        pollTask = nil

        activeAlarmID = nil
        activeRecordingURL = nil
        audioManager.stopAlarmLoop()
    }

    private func scanAllAlarms() async {
        let alarms = (try? AlarmManager.shared.alarms) ?? []
        for alarm in alarms {
            await handle(alarm: alarm)
        }
    }

    private func handle(alarm: Alarm) async {
        guard let recordingURL = AlarmService.shared.recordingURL(for: alarm.id) else {
            return
        }

        guard shouldStartPlayback(for: alarm) else {
            return
        }

        if activeAlarmID == alarm.id, activeRecordingURL == recordingURL {
            return
        }

        do {
            try audioManager.playAlarmLoop(url: recordingURL, fadeIn: true)
            activeAlarmID = alarm.id
            activeRecordingURL = recordingURL
        } catch {
            print("Custom alarm playback failed: \(error.localizedDescription)")
        }
    }

    private func shouldStartPlayback(for alarm: Alarm) -> Bool {
        guard let fireDate = fixedDate(for: alarm) else { return false }
        let now = Date()
        return now >= fireDate && now <= fireDate.addingTimeInterval(60)
    }

    private func fixedDate(for alarm: Alarm) -> Date? {
        guard let schedule = alarm.schedule else { return nil }
        guard case let .fixed(date) = schedule else { return nil }
        return date
    }

    private func stopPlaybackIfActiveAlarmDisappeared(alarms: [Alarm]) async {
        guard let activeAlarmID else { return }
        if alarms.contains(where: { $0.id == activeAlarmID }) {
            return
        }

        self.activeAlarmID = nil
        self.activeRecordingURL = nil
        audioManager.stopAlarmLoop()
    }
}
