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

    // WHY: The app only needs to branch on "usable" versus "needs permission UI",
    // and EventKit can report either `.authorized` or `.fullAccess` depending on OS/runtime.
    var hasCalendarAccess: Bool {
        Self.hasCalendarAccess(status: authorizationStatus)
    }

    var shouldShowPermissionUI: Bool {
        switch authorizationStatus {
        case .notDetermined, .denied:
            return true
        default:
            return false
        }
    }

    static func hasCalendarAccess(status: EKAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .fullAccess:
            return true
        default:
            return false
        }
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    // request calendar permission
    func requestAccess() async -> Bool {
        refreshAuthorizationStatus()
        guard !hasCalendarAccess else { return true }

        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            refreshAuthorizationStatus()
            return granted && hasCalendarAccess
        } catch {
            print("Calendar access error:", error)
            refreshAuthorizationStatus()
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
        event.calendar = getOrCreateDateAlarmCalendar() ?? eventStore.defaultCalendarForNewEvents
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
            try eventStore.save(event, span: .futureEvents)
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
        // ✅ Remove by event ID if we have it
        if let eventID = getEventID(for: alarmID),
           let event = eventStore.event(withIdentifier: eventID) {
            try? eventStore.remove(event, span: .futureEvents)
            print("✅ Removed from calendar: \(alarmID)")
        }
        removeEventID(for: alarmID)

        // ✅ Also search by note to catch any orphaned events
        let start = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let end = Calendar.current.date(byAdding: .year, value: 10, to: Date()) ?? Date()
        let calendars = eventStore.calendars(for: .event)
        let dateAlarmCal = calendars.filter { $0.title == "Date Alarm" }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: dateAlarmCal.isEmpty ? nil : dateAlarmCal)
        let events = eventStore.events(matching: predicate)
        for event in events {
            if event.notes == "Alarm set from Date Alarm app" {
                let eventAlarmID = event.startDate.timeIntervalSince1970.description
                if eventAlarmID == alarmID {
                    try? eventStore.remove(event, span: .futureEvents)
                }
            }
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
    private func getOrCreateDateAlarmCalendar() -> EKCalendar? {
        let calendars = eventStore.calendars(for: .event)
        if let existing = calendars.first(where: { $0.title == "Date Alarm" }) {
            return existing
        }
        let newCalendar = EKCalendar(for: .event, eventStore: eventStore)
        newCalendar.title = "Date Alarm"
        newCalendar.cgColor = UIColor.orange.cgColor
        if let source = eventStore.sources.first(where: { $0.sourceType == .local }) {
            newCalendar.source = source
        } else if let source = eventStore.sources.first {
            newCalendar.source = source
        }
        do {
            try eventStore.saveCalendar(newCalendar, commit: true)
            return newCalendar
        } catch {
            print("Failed to create Date Alarm calendar:", error)
            return nil
        }
    }
    func removeAllCalendarEvents() {
        Task {
            _ = await requestAccess()
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
            let map = getEventMap()
            for (alarmID, _) in map {
                removeAlarmFromCalendar(alarmID: alarmID)
            }
            UserDefaults.standard.removeObject(forKey: "calendarEventMap")
            let start = Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? Date()
            let end = Calendar.current.date(byAdding: .year, value: 10, to: Date()) ?? Date()
            let calendars = eventStore.calendars(for: .event)
            let dateAlarmCal = calendars.first(where: { $0.title == "Date Alarm" })
            let searchCals = dateAlarmCal.map { [$0] }
            let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: searchCals)
            let events = eventStore.events(matching: predicate)
            for event in events {
                try? eventStore.remove(event, span: .futureEvents)
            }
            print("✅ All Date Alarm events removed, calendar kept")
        }
    }
    func requestPermissionIfNeeded() async {
        let store = EKEventStore()
        _ = try? await store.requestFullAccessToEvents()
    }
    func removeAllDateAlarmEvents() async {
        // ✅ Only run if already authorized — don't ask for permission
        refreshAuthorizationStatus()
        guard hasCalendarAccess else { return }
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
