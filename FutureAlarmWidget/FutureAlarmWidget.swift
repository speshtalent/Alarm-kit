import WidgetKit
import SwiftUI

// MARK: - App Group
private let appGroupID = "group.com.speshtalent.FutureAlarm26"
private let dateKey    = "widgetNextAlarmDate"
private let labelKey   = "widgetNextAlarmLabel"
private let upcomingKey = "widgetUpcomingAlarms"

// MARK: - Entry
struct FutureAlarmEntry: TimelineEntry {
    let date: Date
    let alarmDate: Date?
    let alarmLabel: String
    let upcomingAlarms: [(date: Date, label: String)]
    let use24Hour: Bool
}

// MARK: - Provider
struct FutureAlarmProvider: TimelineProvider {

    func placeholder(in context: Context) -> FutureAlarmEntry {
        FutureAlarmEntry(
            date: Date(),
            alarmDate: Date().addingTimeInterval(8.5 * 3600),
            alarmLabel: "Morning Coffee",
            upcomingAlarms: [
                (Date().addingTimeInterval(8.5 * 3600), "Morning Coffee"),
                (Date().addingTimeInterval(18 * 3600), "Evening Walk"),
                (Date().addingTimeInterval(26 * 3600), "Meeting")
            ],
            use24Hour: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FutureAlarmEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FutureAlarmEntry>) -> Void) {
        let entry = readEntry()
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func readEntry() -> FutureAlarmEntry {
        let ud = UserDefaults(suiteName: appGroupID)

        let interval = ud?.double(forKey: dateKey) ?? 0
        let alarmDate: Date? = interval > 1 ? Date(timeIntervalSince1970: interval) : nil
        let label = ud?.string(forKey: labelKey) ?? "No Alarm"

        var upcomingAlarms: [(date: Date, label: String)] = []
        if let jsonString = ud?.string(forKey: upcomingKey),
           let jsonData = jsonString.data(using: .utf8),
           let list = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
            upcomingAlarms = list.compactMap { item -> (Date, String)? in
                guard let ts = item["date"] as? TimeInterval,
                      let lbl = item["label"] as? String else { return nil }
                return (Date(timeIntervalSince1970: ts), lbl)
            }
        }

        let use24Hour = UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")?.bool(forKey: "use24HourFormat") ?? false

        return FutureAlarmEntry(
            date: Date(),
            alarmDate: alarmDate,
            alarmLabel: label,
            upcomingAlarms: upcomingAlarms,
            use24Hour: use24Hour
        )
    }
}

// MARK: - Helpers
private func dayLabel(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) { return "Today" }
    if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
    let f = DateFormatter(); f.dateFormat = "EEE, MMM d"
    return f.string(from: date)
}

private func timeString(_ date: Date, use24Hour: Bool) -> String {
    let f = DateFormatter()
    f.dateFormat = use24Hour ? "HH:mm" : "h:mm"
    return f.string(from: date)
}

private func ampm(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "a"
    return f.string(from: date).uppercased()
}

private func isAlarmPast(_ date: Date) -> Bool {
    return date <= Date()
}

// MARK: - Design Tokens
private let orange     = Color(red: 1.0,  green: 0.42, blue: 0.0)
private let orangeDim  = Color(red: 1.0,  green: 0.42, blue: 0.0).opacity(0.18)
private let orangeLine = Color(red: 1.0,  green: 0.42, blue: 0.0).opacity(0.30)
private let bg         = Color(red: 0.071, green: 0.071, blue: 0.078)
private let textPri    = Color.white
private let textSec    = Color(white: 0.55)

// MARK: - SMALL Widget
struct SmallView: View {
    let entry: FutureAlarmEntry

    var body: some View {
        if let d = entry.alarmDate, !isAlarmPast(d) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(orange)
                    Text("NEXT ALARM")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(orange)
                        .tracking(1.2)
                }
                .padding(.bottom, 8)

                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(timeString(d, use24Hour: entry.use24Hour))
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(textPri)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    if !entry.use24Hour {
                        Text(ampm(d))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(orange)
                            .padding(.bottom, 4)
                    }
                }
                .padding(.bottom, 4)

                Text(dayLabel(d))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(orangeDim, in: Capsule())
                    .padding(.bottom, 6)

                Text(entry.alarmLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(textSec)
                    .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(bg, for: .widget)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "alarm")
                    .font(.system(size: 26))
                    .foregroundStyle(orange.opacity(0.4))
                Text("Set New\nAlarm")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(textSec)
                    .lineSpacing(2)
                Text("Tap to add")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(textSec.opacity(0.5))
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(bg, for: .widget)
        }
    }
}

// MARK: - MEDIUM Widget
struct MediumView: View {
    let entry: FutureAlarmEntry

    var body: some View {
        if let d = entry.alarmDate, !isAlarmPast(d) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Image(systemName: "alarm.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(orange)
                        Text("FUTURE ALARM")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(orange)
                            .tracking(1.2)
                    }
                    .padding(.bottom, 10)

                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(timeString(d, use24Hour: entry.use24Hour))
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundStyle(textPri)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        if !entry.use24Hour {
                            Text(ampm(d))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(orange)
                                .padding(.bottom, 5)
                        }
                    }
                    .padding(.bottom, 6)

                    Text(entry.alarmLabel)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(textSec)
                        .lineLimit(1)

                    Spacer()

                    Text(dayLabel(d))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(orangeDim, in: Capsule())
                }
                .padding(.leading, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(orangeLine)
                    .frame(width: 1)
                    .padding(.vertical, 12)

                VStack(alignment: .leading, spacing: 0) {
                    Text("UPCOMING")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .foregroundStyle(textSec)
                        .tracking(1.2)
                        .padding(.bottom, 8)

                    let upcoming = entry.upcomingAlarms.filter { !isAlarmPast($0.date) }.prefix(3)

                    if upcoming.isEmpty {
                        Text("No more\nalarms")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(textSec.opacity(0.5))
                    } else {
                        ForEach(Array(upcoming.enumerated()), id: \.offset) { _, alarm in
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(alignment: .lastTextBaseline, spacing: 2) {
                                    Text(timeString(alarm.date, use24Hour: entry.use24Hour))
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(textPri)
                                    if !entry.use24Hour {
                                        Text(ampm(alarm.date))
                                            .font(.system(size: 9, weight: .bold, design: .rounded))
                                            .foregroundStyle(orange)
                                    }
                                }
                                Text(dayLabel(alarm.date))
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(textSec)
                            }
                            .padding(.bottom, 7)
                        }
                    }
                    Spacer()
                }
                .padding(.leading, 12)
                .padding(.trailing, 12)
                .padding(.vertical, 14)
                .frame(width: 120, alignment: .leading)
            }
            .containerBackground(bg, for: .widget)
        } else {
            HStack(spacing: 14) {
                Image(systemName: "alarm")
                    .font(.system(size: 36))
                    .foregroundStyle(orange.opacity(0.35))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set New Alarm")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(textSec)
                    Text("Open Future Alarm to set one")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(textSec.opacity(0.5))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(bg, for: .widget)
        }
    }
}

// MARK: - LARGE Widget
struct LargeView: View {
    let entry: FutureAlarmEntry

    var body: some View {
        if let d = entry.alarmDate, !isAlarmPast(d) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(orange)
                    Text("FUTURE ALARM")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(orange)
                        .tracking(1.5)
                    Spacer()
                }
                .padding(.bottom, 16)

                Text("NEXT ALARM")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(textSec)
                    .tracking(2)
                    .padding(.bottom, 6)

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(timeString(d, use24Hour: entry.use24Hour))
                        .font(.system(size: 64, weight: .black, design: .rounded))
                        .foregroundStyle(textPri)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if !entry.use24Hour {
                        Text(ampm(d))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(orange)
                            .padding(.bottom, 8)
                    }
                }
                .padding(.bottom, 8)

                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13))
                        .foregroundStyle(orange)
                    Text(dayLabel(d))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(orange)
                }
                .padding(.bottom, 6)

                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(textSec)
                    Text(entry.alarmLabel)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(textPri)
                        .lineLimit(1)
                }
                .padding(.bottom, 16)

                Rectangle()
                    .fill(orangeLine)
                    .frame(height: 1)
                    .padding(.bottom, 14)

                Text("UPCOMING")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(textSec)
                    .tracking(2)
                    .padding(.bottom, 10)

                let upcoming = entry.upcomingAlarms.filter { !isAlarmPast($0.date) }.prefix(4)

                if upcoming.isEmpty {
                    Text("No more upcoming alarms")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(textSec.opacity(0.5))
                } else {
                    ForEach(Array(upcoming.enumerated()), id: \.offset) { _, alarm in
                        HStack {
                            HStack(alignment: .lastTextBaseline, spacing: 3) {
                                Text(timeString(alarm.date, use24Hour: entry.use24Hour))
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(textPri)
                                if !entry.use24Hour {
                                    Text(ampm(alarm.date))
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(orange)
                                }
                            }
                            Spacer()
                            Text(dayLabel(alarm.date))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(textSec)
                            Spacer()
                            Text(alarm.label)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(textSec)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(orangeDim, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.bottom, 5)
                    }
                }

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(bg, for: .widget)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "alarm")
                    .font(.system(size: 52))
                    .foregroundStyle(orange.opacity(0.3))
                Text("Set New Alarm")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(textSec)
                Text("Open Future Alarm\nto set your next alarm")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(textSec.opacity(0.5))
                    .lineSpacing(4)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(bg, for: .widget)
        }
    }
}

// MARK: - Lock Screen Widget
// MARK: - Lock Screen Widget
struct LockScreenView: View {
    let entry: FutureAlarmEntry

    var body: some View {
        if entry.upcomingAlarms.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "alarm")
                    .font(.system(size: 13, weight: .semibold))
                    .widgetAccentable()
                Text("No upcoming alarms")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .containerBackground(.clear, for: .widget)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(0..<min(entry.upcomingAlarms.count, 3), id: \.self) { i in
                    let alarm = entry.upcomingAlarms[i]
                    let endDate = alarm.date.addingTimeInterval(600) // ✅ 10 min duration
                    let opacity = i == 0 ? 1.0 : (i == 1 ? 0.65 : 0.4)

                    HStack(spacing: 6) {
                        // ✅ Orange line on left
                        Rectangle()
                            .fill(Color.orange.opacity(opacity))
                            .frame(width: 2)
                            .widgetAccentable()

                        VStack(alignment: .leading, spacing: 1) {
                            // ✅ Alarm name
                            Text(alarm.label)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .opacity(opacity)
                                .widgetAccentable()

                            // ✅ Time range + day
                            Text("\(fullTimeString(alarm.date, use24Hour: entry.use24Hour)) – \(fullTimeString(endDate, use24Hour: entry.use24Hour)) · \(shortDay(alarm.date))")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .lineLimit(1)
                                .opacity(opacity * 0.8)
                        }
                    }
                }
            }
            .containerBackground(.clear, for: .widget)
        }
    }

    private func fullTimeString(_ date: Date, use24Hour: Bool) -> String {
        let f = DateFormatter()
        f.dateFormat = use24Hour ? "HH:mm" : "h:mm a"
        return f.string(from: date)
    }

    private func shortDay(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}
// MARK: - Entry Views
struct FutureAlarmEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: FutureAlarmEntry
    var body: some View {
        switch family {
        case .systemSmall:  SmallView(entry: entry)
        case .systemMedium: MediumView(entry: entry)
        case .systemLarge:  LargeView(entry: entry)
        default:            SmallView(entry: entry)
        }
    }
}

// MARK: - Widget Definitions
struct FutureAlarmWidget: Widget {
    let kind = "FutureAlarmWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FutureAlarmProvider()) { entry in
            FutureAlarmEntryView(entry: entry)
        }
        .configurationDisplayName("Future Alarm")
        .description("See your next alarm details.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct LockScreenWidget: Widget {
    let kind = "LockScreenWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FutureAlarmProvider()) { entry in
            LockScreenView(entry: entry)
        }
        .configurationDisplayName("Upcoming Alarms")
        .description("Shows your upcoming alarms on the lock screen.")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Previews
#if DEBUG && targetEnvironment(simulator)
#Preview("Small", as: .systemSmall) {
    FutureAlarmWidget()
} timeline: {
    FutureAlarmEntry(date: .now, alarmDate: Date().addingTimeInterval(8.5 * 3600), alarmLabel: "Morning Coffee", upcomingAlarms: [
        (Date().addingTimeInterval(8.5 * 3600), "Morning Coffee"),
        (Date().addingTimeInterval(18 * 3600), "Evening Walk"),
        (Date().addingTimeInterval(26 * 3600), "Meeting")
    ], use24Hour: false)
}

#Preview("Medium", as: .systemMedium) {
    FutureAlarmWidget()
} timeline: {
    FutureAlarmEntry(date: .now, alarmDate: Date().addingTimeInterval(8.5 * 3600), alarmLabel: "Morning Coffee", upcomingAlarms: [
        (Date().addingTimeInterval(8.5 * 3600), "Morning Coffee"),
        (Date().addingTimeInterval(18 * 3600), "Evening Walk"),
        (Date().addingTimeInterval(26 * 3600), "Meeting")
    ], use24Hour: false)
}

#Preview("Large", as: .systemLarge) {
    FutureAlarmWidget()
} timeline: {
    FutureAlarmEntry(date: .now, alarmDate: Date().addingTimeInterval(8.5 * 3600), alarmLabel: "Morning Coffee", upcomingAlarms: [
        (Date().addingTimeInterval(8.5 * 3600), "Morning Coffee"),
        (Date().addingTimeInterval(18 * 3600), "Evening Walk"),
        (Date().addingTimeInterval(26 * 3600), "Meeting"),
        (Date().addingTimeInterval(34 * 3600), "Doctor Appointment")
    ], use24Hour: false)
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    LockScreenWidget()
} timeline: {
    FutureAlarmEntry(
        date: .now,
        alarmDate: Date().addingTimeInterval(8.5 * 3600),
        alarmLabel: "Morning Coffee",
        upcomingAlarms: [
            (Date().addingTimeInterval(8.5 * 3600), "Morning Coffee"),
            (Date().addingTimeInterval(18 * 3600), "Evening Walk"),
            (Date().addingTimeInterval(26 * 3600), "Meeting")
        ],
        use24Hour: false
    )
}
#endif
