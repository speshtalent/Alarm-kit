import Foundation
import EventKit
import Combine
import UIKit

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
    func addAlarmToCalendar(title: String, date: Date, alarmID: String, weekday: Int? = nil) async -> Bool {
        let granted = await requestAccess()
        guard granted else {
            return false
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = "⏰ \(title)"
        event.startDate = date
        event.endDate = date.addingTimeInterval(3600)
        event.calendar = eventStore.defaultCalendarForNewEvents
        event.notes = "Alarm set from Date Alarm app"

        // ✅ Add weekly recurrence if weekday is provided
        if let weekday = weekday {
            let dayOfWeek = EKRecurrenceDayOfWeek(EKWeekday(rawValue: weekday)!)
            let rule = EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                daysOfTheWeek: [dayOfWeek],
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: nil
            )
            event.recurrenceRules = [rule]
        }

        do {
            try eventStore.save(event, span: .thisEvent)
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
            // ✅ Use .futureEvents to remove all recurring occurrences
            try eventStore.remove(event, span: .futureEvents)
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
        Task {
            // ✅ Always request permission
            _ = await requestAccess()
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
            
            // ✅ Remove using saved map
            let map = getEventMap()
            for (alarmID, _) in map {
                removeAlarmFromCalendar(alarmID: alarmID)
            }
            UserDefaults.standard.removeObject(forKey: "calendarEventMap")
            
            // ✅ Also search and remove any remaining events by note
            let start = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
            let end = Calendar.current.date(byAdding: .year, value: 5, to: Date()) ?? Date()
            let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
            let events = eventStore.events(matching: predicate)
            for event in events {
                if event.notes == "Alarm set from Date Alarm app" {
                    try? eventStore.remove(event, span: .futureEvents)
                }
            }
            print("✅ All calendar events removed")
        }
    }
    func requestPermissionIfNeeded() async {
        let store = EKEventStore()
        _ = try? await store.requestFullAccessToEvents()
    }
    func removeAllDateAlarmEvents() async {
        // ✅ Only run if already authorized — don't ask for permission
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let granted = await requestAccess()
        guard granted else { return }
        
        // ✅ Search for events with our app note in next 5 years
        let start = Date()
        let end = Calendar.current.date(byAdding: .year, value: 5, to: start) ?? start
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        for event in events {
            if event.notes == "Alarm set from Date Alarm app" {
                try? eventStore.remove(event, span: .futureEvents)
            }
        }
        UserDefaults.standard.removeObject(forKey: "calendarEventMap")
        print("✅ Cleared all Date Alarm calendar events")
    }
}
