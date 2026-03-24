import WidgetKit
import SwiftUI

// MARK: - Timeline Entry
struct FutureAlarmEntry: TimelineEntry {
    let date: Date
    let alarmDate: Date?
    let alarmLabel: String
}

// MARK: - Timeline Provider
struct FutureAlarmProvider: TimelineProvider {

    func placeholder(in context: Context) -> FutureAlarmEntry {
        FutureAlarmEntry(
            date: Date(),
            alarmDate: Date().addingTimeInterval(3600),
            alarmLabel: "Morning Coffee"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FutureAlarmEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FutureAlarmEntry>) -> Void) {
        let entry = entry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func entry() -> FutureAlarmEntry {
        let userDefaults = UserDefaults(suiteName: "group.com.maniraj48.MyAlarmApp2026")
        let alarmDate = userDefaults?.object(forKey: "widgetNextAlarmDate") as? Date
        let alarmLabel = userDefaults?.string(forKey: "widgetNextAlarmLabel") ?? "No Alarm Set"
        return FutureAlarmEntry(date: Date(), alarmDate: alarmDate, alarmLabel: alarmLabel)
    }
}

// MARK: - Small Widget View
struct SmallWidgetView: View {
    let entry: FutureAlarmEntry
    // ✅ ADDED — detect system color scheme
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // ✅ UPDATED — dynamic background
            Color("AppBackground")
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 14, weight: .bold))
                    Text("Next Alarm")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                }

                if let alarmDate = entry.alarmDate {
                    Text(alarmDate.formatted(
                        Date.FormatStyle()
                            .hour(.defaultDigits(amPM: .abbreviated))
                            .minute(.twoDigits)
                    ))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    // ✅ UPDATED — dynamic text
                    .foregroundStyle(Color("PrimaryText"))

                    Text(dayText(for: alarmDate))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        // ✅ UPDATED — dynamic text
                        .foregroundStyle(Color("SecondaryText"))

                    Text(entry.alarmLabel)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange.opacity(0.8))
                        .lineLimit(1)
                } else {
                    Text("No Alarm")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        // ✅ UPDATED — dynamic text
                        .foregroundStyle(Color("SecondaryText"))
                    Text("Tap to set one")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Color("SecondaryText").opacity(0.6))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func dayText(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Medium Widget View
struct MediumWidgetView: View {
    let entry: FutureAlarmEntry
    // ✅ ADDED — detect system color scheme
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // ✅ UPDATED — dynamic background
            Color("AppBackground")
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "alarm.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 14, weight: .bold))
                        Text("Future Alarm")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.orange)
                    }

                    if let alarmDate = entry.alarmDate {
                        Text(alarmDate.formatted(
                            Date.FormatStyle()
                                .hour(.defaultDigits(amPM: .abbreviated))
                                .minute(.twoDigits)
                        ))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        // ✅ UPDATED — dynamic text
                        .foregroundStyle(Color("PrimaryText"))

                        Text(entry.alarmLabel)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            // ✅ UPDATED — dynamic text
                            .foregroundStyle(Color("PrimaryText").opacity(0.8))
                            .lineLimit(1)
                    } else {
                        Text("No Alarm")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            // ✅ UPDATED — dynamic text
                            .foregroundStyle(Color("SecondaryText"))
                        Text("Tap to set one")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Color("SecondaryText").opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let alarmDate = entry.alarmDate {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(dayText(for: alarmDate))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.orange)
                        Text(hoursAway(for: alarmDate))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            // ✅ UPDATED — dynamic text
                            .foregroundStyle(Color("SecondaryText"))
                            .multilineTextAlignment(.trailing)
                    }
                    .frame(width: 100, alignment: .trailing)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func dayText(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d"
            return formatter.string(from: date)
        }
    }

    private func hoursAway(for date: Date) -> String {
        let diff = date.timeIntervalSince(Date())
        if diff <= 0 { return "Now!" }
        let hours = Int(diff / 3600)
        let minutes = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours == 0 {
            return "in \(minutes)m"
        } else if minutes == 0 {
            return "in \(hours)h"
        } else {
            return "in \(hours)h \(minutes)m"
        }
    }
}

// MARK: - Widget Entry View
struct FutureAlarmWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: FutureAlarmEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Widget
struct FutureAlarmWidget: Widget {
    let kind: String = "FutureAlarmWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FutureAlarmProvider()) { entry in
            FutureAlarmWidgetEntryView(entry: entry)
                // ✅ UPDATED — dynamic container background
                .containerBackground(Color("AppBackground"), for: .widget)
        }
        .configurationDisplayName("Future Alarm")
        .description("See your next alarm at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Preview
#Preview(as: .systemSmall) {
    FutureAlarmWidget()
} timeline: {
    FutureAlarmEntry(date: .now, alarmDate: Date().addingTimeInterval(3600), alarmLabel: "Morning Coffee")
    FutureAlarmEntry(date: .now, alarmDate: nil, alarmLabel: "No Alarm Set")
}

#Preview(as: .systemMedium) {
    FutureAlarmWidget()
} timeline: {
    FutureAlarmEntry(date: .now, alarmDate: Date().addingTimeInterval(3600), alarmLabel: "Morning Coffee")
    FutureAlarmEntry(date: .now, alarmDate: nil, alarmLabel: "No Alarm Set")
}
