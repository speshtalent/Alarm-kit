import Foundation
import EventKit
import Combine

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()
    private let eventStore = EKEventStore()
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    // request calendar permission
    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            return granted
        } catch {
            print("Calendar access error:", error)
            return false
        }
    }

    // add alarm to iPhone Calendar
    // returns eventIdentifier so we can delete it later
    func addAlarmToCalendar(title: String, date: Date, alarmID: String) async -> Bool {
        let granted = await requestAccess()
        guard granted else { return false }

        let event = EKEvent(eventStore: eventStore)
        event.title = "⏰ \(title)"
        event.startDate = date
        event.endDate = date.addingTimeInterval(3600)
        event.calendar = eventStore.defaultCalendarForNewEvents
        event.notes = "Alarm set from Date Alarm app"

        do {
            try eventStore.save(event, span: .thisEvent)
            // save eventIdentifier linked to alarmID
            // so we can find and delete it later
            saveEventID(event.eventIdentifier, for: alarmID)
            print("✅ Added to calendar: \(title)")
            return true
        } catch {
            print("Calendar save error:", error)
            return false
        }
    }

    // delete event from iPhone Calendar when alarm is deleted
    func removeAlarmFromCalendar(alarmID: String) {
        guard let eventID = getEventID(for: alarmID) else { return }
        guard let event = eventStore.event(withIdentifier: eventID) else { return }
        do {
            try eventStore.remove(event, span: .thisEvent)
            removeEventID(for: alarmID)
            print("✅ Removed from calendar: \(alarmID)")
        } catch {
            print("Calendar remove error:", error)
        }
    }

    // MARK: - Store event IDs linked to alarm IDs
    // saves eventIdentifier → alarmID mapping in UserDefaults
    private func saveEventID(_ eventID: String, for alarmID: String) {
        var map = getEventMap()
        map[alarmID] = eventID
        UserDefaults.standard.set(map, forKey: "calendarEventMap")
    }

    private func getEventID(for alarmID: String) -> String? {
        return getEventMap()[alarmID]
    }

    private func removeEventID(for alarmID: String) {
        var map = getEventMap()
        map.removeValue(forKey: alarmID)
        UserDefaults.standard.set(map, forKey: "calendarEventMap")
    }

    private func getEventMap() -> [String: String] {
        return UserDefaults.standard.dictionary(forKey: "calendarEventMap") as? [String: String] ?? [:]
    }
    func removeAllCalendarEvents() {
        let map = getEventMap()
        for (alarmID, _) in map {
            removeAlarmFromCalendar(alarmID: alarmID)
        }
        UserDefaults.standard.removeObject(forKey: "calendarEventMap")
        print("✅ All calendar events removed")
    }
}
