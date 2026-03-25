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
        let userDefaults = UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")
        let alarmDate = userDefaults?.object(forKey: "widgetNextAlarmDate") as? Date
        let alarmLabel = userDefaults?.string(forKey: "widgetNextAlarmLabel") ?? "No Alarm Set"
        return FutureAlarmEntry(date: Date(), alarmDate: alarmDate, alarmLabel: alarmLabel)
    }
}

// MARK: - Helper Functions
private func dayText(for date: Date) -> String {
    if Calendar.current.isDateInToday(date) { return "Today" }
    else if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
    else {
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
    if hours == 0 { return "\(minutes)m" }
    else if minutes == 0 { return "\(hours)h" }
    else { return "\(hours)h \(minutes)m" }
}

// MARK: - WIDGET 1 — Full Details (Small/Medium/Large)
struct SmallWidgetView: View {
    let entry: FutureAlarmEntry
    var body: some View {
        ZStack {
            Color("AppBackground")
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12, weight: .bold))
                    Text("Next Alarm")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                }
                if let alarmDate = entry.alarmDate {
                    Text(alarmDate.formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("PrimaryText"))
                        .minimumScaleFactor(0.8)
                    Text(dayText(for: alarmDate))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)
                    Text(entry.alarmLabel)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color("SecondaryText"))
                        .lineLimit(1)
                } else {
                    Text("No Alarm")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("SecondaryText"))
                    Text("Tap to set")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Color("SecondaryText").opacity(0.6))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

struct MediumWidgetView: View {
    let entry: FutureAlarmEntry
    var body: some View {
        ZStack {
            Color("AppBackground")
            if let alarmDate = entry.alarmDate {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "alarm.fill")
                                .foregroundStyle(.orange)
                                .font(.system(size: 13, weight: .bold))
                            Text("Future Alarm")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.orange)
                        }
                        Text(alarmDate.formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(Color("PrimaryText"))
                            .minimumScaleFactor(0.8)
                        Text(entry.alarmLabel)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color("SecondaryText"))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle()
                        .fill(Color.orange.opacity(0.3))
                        .frame(width: 1)
                        .padding(.vertical, 8)
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(dayText(for: alarmDate))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.trailing)
                        VStack(alignment: .trailing, spacing: 2) {
                            Image(systemName: "clock")
                                .foregroundStyle(Color("SecondaryText"))
                                .font(.system(size: 16))
                            Text(hoursAway(for: alarmDate))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color("SecondaryText"))
                        }
                    }
                    .frame(width: 90, alignment: .trailing)
                }
                .padding(16)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "alarm.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 13, weight: .bold))
                        Text("Future Alarm")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                    Text("No Alarm Set")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("SecondaryText"))
                    Text("Open app to set an alarm")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color("SecondaryText").opacity(0.6))
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }
}

struct LargeWidgetView: View {
    let entry: FutureAlarmEntry
    var body: some View {
        ZStack {
            Color("AppBackground")
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 16, weight: .bold))
                    Text("Future Alarm")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                    Spacer()
                }
                .padding(.bottom, 20)
                if let alarmDate = entry.alarmDate {
                    Text("NEXT ALARM")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color("SecondaryText"))
                        .tracking(1.5)
                        .padding(.bottom, 4)
                    Text(alarmDate.formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits)))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("PrimaryText"))
                        .minimumScaleFactor(0.7)
                        .padding(.bottom, 8)
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .foregroundStyle(.orange)
                            .font(.system(size: 14))
                        Text(dayText(for: alarmDate))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                    .padding(.bottom, 8)
                    HStack(spacing: 6) {
                        Image(systemName: "tag.fill")
                            .foregroundStyle(Color("SecondaryText"))
                            .font(.system(size: 13))
                        Text(entry.alarmLabel)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Color("PrimaryText"))
                            .lineLimit(1)
                    }
                    .padding(.bottom, 20)
                    Rectangle()
                        .fill(Color.orange.opacity(0.25))
                        .frame(height: 1)
                        .padding(.bottom, 16)
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.15))
                                .frame(width: 40, height: 40)
                            Image(systemName: "clock.fill")
                                .foregroundStyle(.orange)
                                .font(.system(size: 18))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Time remaining")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Color("SecondaryText"))
                            Text(hoursAway(for: alarmDate))
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(Color("PrimaryText"))
                        }
                    }
                } else {
                    Spacer()
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "alarm")
                            .foregroundStyle(.orange.opacity(0.4))
                            .font(.system(size: 48))
                        Text("No Alarm Set")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color("SecondaryText"))
                        Text("Open Future Alarm app\nto set your next alarm")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Color("SecondaryText").opacity(0.6))
                            .lineSpacing(4)
                    }
                    Spacer()
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - WIDGET 2 — Countdown (time remaining)
struct CountdownWidgetView: View {
    let entry: FutureAlarmEntry
    var body: some View {
        ZStack {
            Color("AppBackground")
            VStack(spacing: 8) {
                Image(systemName: "timer")
                    .foregroundStyle(.orange)
                    .font(.system(size: 24, weight: .bold))
                if let alarmDate = entry.alarmDate {
                    Text(hoursAway(for: alarmDate))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("PrimaryText"))
                        .minimumScaleFactor(0.7)
                    Text("until alarm")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color("SecondaryText"))
                    Text(entry.alarmLabel)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange.opacity(0.8))
                        .lineLimit(1)
                } else {
                    Text("No Alarm")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("SecondaryText"))
                    Text("Tap to set")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Color("SecondaryText").opacity(0.6))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - WIDGET 3 — Time Only
struct TimeOnlyWidgetView: View {
    let entry: FutureAlarmEntry
    var body: some View {
        ZStack {
            Color("AppBackground")
            VStack(spacing: 4) {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 20, weight: .bold))
                if let alarmDate = entry.alarmDate {
                    // Hour
                    Text(alarmDate.formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("PrimaryText"))
                        .minimumScaleFactor(0.7)
                    // AM/PM
                    Text(alarmDate.formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute(.omitted)))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                } else {
                    Text("--:--")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("SecondaryText"))
                    Text("No alarm")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Color("SecondaryText").opacity(0.6))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Widget Entry Views
struct FutureAlarmWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: FutureAlarmEntry
    var body: some View {
        switch family {
        case .systemSmall: SmallWidgetView(entry: entry)
        case .systemMedium: MediumWidgetView(entry: entry)
        case .systemLarge: LargeWidgetView(entry: entry)
        default: SmallWidgetView(entry: entry)
        }
    }
}

struct CountdownWidgetEntryView: View {
    let entry: FutureAlarmEntry
    var body: some View {
        CountdownWidgetView(entry: entry)
    }
}

struct TimeOnlyWidgetEntryView: View {
    let entry: FutureAlarmEntry
    var body: some View {
        TimeOnlyWidgetView(entry: entry)
    }
}

// MARK: - Widget 1 — Full Details
struct FutureAlarmWidget: Widget {
    let kind: String = "FutureAlarmWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FutureAlarmProvider()) { entry in
            FutureAlarmWidgetEntryView(entry: entry)
                .containerBackground(Color("AppBackground"), for: .widget)
        }
        .configurationDisplayName("Future Alarm")
        .description("See your next alarm details.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget 2 — Countdown
struct CountdownWidget: Widget {
    let kind: String = "CountdownWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FutureAlarmProvider()) { entry in
            CountdownWidgetEntryView(entry: entry)
                .containerBackground(Color("AppBackground"), for: .widget)
        }
        .configurationDisplayName("Alarm Countdown")
        .description("See time remaining until alarm.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Widget 3 — Time Only
struct TimeOnlyWidget: Widget {
    let kind: String = "TimeOnlyWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FutureAlarmProvider()) { entry in
            TimeOnlyWidgetEntryView(entry: entry)
                .containerBackground(Color("AppBackground"), for: .widget)
        }
        .configurationDisplayName("Alarm Time")
        .description("Shows only your next alarm time.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Previews
#Preview(as: .systemSmall) {
    FutureAlarmWidget()
} timeline: {
    FutureAlarmEntry(date: .now, alarmDate: Date().addingTimeInterval(3600), alarmLabel: "Morning Coffee")
}

#Preview(as: .systemMedium) {
    FutureAlarmWidget()
} timeline: {
    FutureAlarmEntry(date: .now, alarmDate: Date().addingTimeInterval(3600), alarmLabel: "Morning Coffee")
}

#Preview(as: .systemLarge) {
    FutureAlarmWidget()
} timeline: {
    FutureAlarmEntry(date: .now, alarmDate: Date().addingTimeInterval(3600), alarmLabel: "Morning Coffee")
}

#Preview(as: .systemSmall) {
    CountdownWidget()
} timeline: {
    FutureAlarmEntry(date: .now, alarmDate: Date().addingTimeInterval(3600), alarmLabel: "Morning Coffee")
}

#Preview(as: .systemSmall) {
    TimeOnlyWidget()
} timeline: {
    FutureAlarmEntry(date: .now, alarmDate: Date().addingTimeInterval(3600), alarmLabel: "Morning Coffee")
}
