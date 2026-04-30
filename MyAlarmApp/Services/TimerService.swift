import Foundation
import Combine
import AlarmKit
import ActivityKit
import UserNotifications

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

    @Published var timers: [TimerViewModel] = []
    @Published var timerViewModels: [TimerViewModel] = []

    private init() {}

    private struct StoredTimer: Codable, Identifiable, Hashable {
        let id: UUID
        let title: String
        let duration: TimeInterval
        let sound: String
        let endDate: Date
    }

    private let timersKey = "LocalTimers"

    private func titleKey(for id: UUID) -> String { "timerTitle_\(id.uuidString)" }
    private func durationKey(for id: UUID) -> String { "timerDuration_\(id.uuidString)" }
    private func soundKey(for id: UUID) -> String { "timerSound_\(id.uuidString)" }
    private func endDateKey(for id: UUID) -> String { "timerEndDate_\(id.uuidString)" }

    // MARK: - Load timers
    func loadTimers() {
        let now = Date()
        let storedTimers = loadStoredTimers()
        let activeTimers = storedTimers.filter { $0.endDate > now }
        if activeTimers.count != storedTimers.count {
            saveStoredTimers(activeTimers)
        }
        timerViewModels = activeTimers.map(makeViewModel).sorted { $0.title < $1.title }
        timers = timerViewModels
        removeMetadataForInactiveTimers(activeIDs: Set(activeTimers.map(\.id.uuidString)))
        Task { await cleanupLegacyAlarmKitTimers(activeIDs: Set(activeTimers.map(\.id.uuidString))) }
    }

    // MARK: - Start timer
    func startTimer(duration: TimeInterval, title: String, sound: String = "nokia.caf") async {
        do {
            await cleanupLegacyAlarmKitTimers(activeIDs: [])
            let id = UUID()
            let endDate = Date().addingTimeInterval(duration)
            let timer = StoredTimer(
                id: id,
                title: title,
                duration: duration,
                sound: sound,
                endDate: endDate
            )
            try await scheduleNotification(for: timer)

            var storedTimers = loadStoredTimers()
            storedTimers.removeAll { $0.id == id }
            storedTimers.append(timer)
            saveStoredTimers(storedTimers)

            UserDefaults.standard.set(title, forKey: titleKey(for: id))
            UserDefaults.standard.set(duration, forKey: durationKey(for: id))
            UserDefaults.standard.set(sound, forKey: soundKey(for: id))
            UserDefaults.standard.set(endDate.timeIntervalSince1970, forKey: endDateKey(for: id))

            let appGroup = UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")
            appGroup?.set(title, forKey: titleKey(for: id))
            appGroup?.set(duration, forKey: durationKey(for: id))
            appGroup?.set(sound, forKey: soundKey(for: id))
            appGroup?.set(endDate.timeIntervalSince1970, forKey: endDateKey(for: id))

            loadTimers()
            print("⏱️ Timer started:", duration, "sound:", sound)

        } catch {
            print("❌ Failed to start timer:", error)
        }
    }

    // MARK: - Cancel timer
    func cancelTimer(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier(for: id)]
        )
        var storedTimers = loadStoredTimers()
        storedTimers.removeAll { $0.id == id }
        saveStoredTimers(storedTimers)
        removeMetadata(for: id)
        Task {
            try? AlarmManager.shared.cancel(id: id)
            await LiveActivityCoordinator.endTimerActivities()
        }
        loadTimers()
        print("🗑️ Timer cancelled")
    }

    func viewModel(for id: UUID) -> TimerViewModel? {
        timerViewModels.first(where: { $0.id == id })
    }

    private func makeViewModel(for timer: StoredTimer) -> TimerViewModel {
        let remaining = max(timer.endDate.timeIntervalSinceNow, 0)

        return TimerViewModel(
            id: timer.id,
            title: timer.title,
            state: remaining > 0 ? .running : .idle,
            totalDuration: max(timer.duration, remaining),
            remainingDuration: remaining,
            sound: timer.sound,
            endDate: remaining > 0 ? timer.endDate : nil
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

    private func removeMetadataForInactiveTimers(activeIDs: Set<String>) {
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in keys where key.hasPrefix("timerDuration_") {
            let id = key.replacingOccurrences(of: "timerDuration_", with: "")
            guard !activeIDs.contains(id), let uuid = UUID(uuidString: id) else { continue }
            removeMetadata(for: uuid)
        }
    }

    private func loadStoredTimers() -> [StoredTimer] {
        guard let data = UserDefaults.standard.data(forKey: timersKey) else { return [] }
        return (try? JSONDecoder().decode([StoredTimer].self, from: data)) ?? []
    }

    private func saveStoredTimers(_ timers: [StoredTimer]) {
        if let data = try? JSONEncoder().encode(timers) {
            UserDefaults.standard.set(data, forKey: timersKey)
        }
    }

    private func notificationIdentifier(for id: UUID) -> String {
        "timer_\(id.uuidString)"
    }

    private func scheduleNotification(for timer: StoredTimer) async throws {
        let content = UNMutableNotificationContent()
        content.title = timer.title
        content.body = "Timer finished"
        content.sound = UNNotificationSound(named: UNNotificationSoundName(timer.sound))

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(timer.endDate.timeIntervalSinceNow, 1),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: notificationIdentifier(for: timer.id),
            content: content,
            trigger: trigger
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    private func cleanupLegacyAlarmKitTimers(activeIDs: Set<String>) async {
        let cancelled = cancelOrphanAlarmKitTimerRecords(activeIDs: activeIDs)
        if cancelled {
            await LiveActivityCoordinator.endTimerActivities()
        }
    }

    /// Cancels zombie AlarmKit alarms that only existed for legacy timers (`schedule == nil`) while local timer state is gone.
    /// Run on launch (via `AlarmService.loadAlarms`) so Dynamic Island does not keep an empty Live Activity.
    @discardableResult
    func cancelOrphanAlarmKitTimerRecords(activeIDs: Set<String>? = nil) -> Bool {
        let resolvedActive = activeIDs ?? Set(loadStoredTimers().map(\.id.uuidString))
        var timerIDs = UserDefaults.standard.dictionaryRepresentation().keys.compactMap { key -> UUID? in
            guard key.hasPrefix("timerDuration_") else { return nil }
            let id = key.replacingOccurrences(of: "timerDuration_", with: "")
            guard !resolvedActive.contains(id) else { return nil }
            return UUID(uuidString: id)
        }
        let alarmKitTimerIDs = (try? AlarmManager.shared.alarms.compactMap { alarm -> UUID? in
            guard alarm.schedule == nil, !resolvedActive.contains(alarm.id.uuidString) else { return nil }
            return alarm.id
        }) ?? []
        timerIDs.append(contentsOf: alarmKitTimerIDs)

        let unique = Set(timerIDs)
        guard !unique.isEmpty else { return false }
        for id in unique {
            try? AlarmManager.shared.cancel(id: id)
        }
        return true
    }
}
