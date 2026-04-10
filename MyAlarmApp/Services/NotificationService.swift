import Foundation
import UserNotifications

final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    // ✅ Request permission
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ Notification permission granted")
            } else {
                print("❌ Notification permission denied")
            }
        }
    }

    // ✅ Schedule both notifications for an alarm
    func scheduleNotifications(for alarmID: UUID, label: String, fireDate: Date) {
        let calendar = Calendar.current

        // ✅ Case 1 — 10 mins before
        let tenMinsBefore = fireDate.addingTimeInterval(-10 * 60)
        if tenMinsBefore > Date() {
            let content = UNMutableNotificationContent()
            content.title = "⏰ Upcoming Alarm"
            content.body = "\(label) rings in 10 minutes!"
            content.sound = .default

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: tenMinsBefore)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "alarm_10min_\(alarmID.uuidString)",
                content: content,
                trigger: trigger
            )
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("❌ 10min notification error: \(error)")
                } else {
                    print("✅ 10min notification scheduled for: \(label) at \(tenMinsBefore)")
                }
            }
        }

        // ✅ Case 2 — Day before at midnight (00:01 AM)
        if let dayBefore = calendar.date(byAdding: .day, value: -1, to: fireDate) {
            var components = calendar.dateComponents([.year, .month, .day], from: dayBefore)
            components.hour = 0
            components.minute = 1

            if let notifDate = calendar.date(from: components), notifDate > Date() {
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "h:mm a"
                let timeStr = timeFormatter.string(from: fireDate)

                let content = UNMutableNotificationContent()
                content.title = "📅 Alarm Tomorrow"
                content.body = "You have \"\(label)\" tomorrow at \(timeStr)"
                content.sound = .default

                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "alarm_daybefore_\(alarmID.uuidString)",
                    content: content,
                    trigger: trigger
                )
                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("❌ Day before notification error: \(error)")
                    } else {
                        print("✅ Day before notification scheduled for: \(label)")
                    }
                }
            }
        }
    }

    // ✅ Cancel notifications when alarm is deleted
    func cancelNotifications(for alarmID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [
                "alarm_10min_\(alarmID.uuidString)",
                "alarm_daybefore_\(alarmID.uuidString)"
            ]
        )
        print("✅ Notifications cancelled for: \(alarmID)")
    }
}
