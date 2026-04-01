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
        // ✅ Save which alarm fired so AlarmHandler plays the right voice file
        UserDefaults.standard.set(alarmID, forKey: "lastFiredAlarmID")
        UserDefaults.standard.set(true, forKey: "pendingVoicePlay")
        NotificationCenter.default.post(name: NSNotification.Name("AlarmDidStop"), object: nil)
        // ✅ Save to history directly via UserDefaults (no AlarmService needed)
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
        try AlarmManager.shared.countdown(id: id)
        return .result()
    }
}
