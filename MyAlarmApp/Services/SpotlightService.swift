import Foundation
import CoreSpotlight

final class SpotlightService {
    static let shared = SpotlightService()
    private init() {}

    func indexAlarms(_ groups: [AlarmService.AlarmGroup]) {
        var items: [CSSearchableItem] = []

        for group in groups {
            guard let fireDate = group.fireDate else { continue }

            let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
            attributeSet.title = group.label
            attributeSet.contentDescription = "Date Alarm · \(fireDate.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))"
            attributeSet.keywords = ["alarm", "date alarm", group.label]

            let item = CSSearchableItem(
                uniqueIdentifier: "alarm_\(group.id.uuidString)",
                domainIdentifier: "com.speshtalent.FutureAlarm26.alarms",
                attributeSet: attributeSet
            )
            item.expirationDate = fireDate
            items.append(item)
        }

        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error = error {
                print("❌ Spotlight error:", error)
            } else {
                print("✅ Spotlight indexed \(items.count) alarms")
            }
        }
    }

    func removeAll() {
        CSSearchableIndex.default().deleteAllSearchableItems { _ in }
    }
}
