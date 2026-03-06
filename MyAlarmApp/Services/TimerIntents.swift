import AppIntents
import AlarmKit

struct StopAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop"

    @Parameter(title: "alarmID")
    var alarmID: String

    init(alarmID: String) { self.alarmID = alarmID }
    init() { self.alarmID = "" }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        try AlarmManager.shared.cancel(id: id)
        // Notify main app to play voice
        UserDefaults.standard.set(true, forKey: "pendingVoicePlay")
        NotificationCenter.default.post(name: NSNotification.Name("AlarmDidStop"), object: nil)
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
        try AlarmManager.shared.countdown(id: id)
        return .result()
    }
}
