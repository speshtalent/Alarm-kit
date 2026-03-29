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
                (Date().addingTimeInterval(18 * 3600), "Evening Walk")
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

private func timeLeft(_ date: Date) -> String {
    let diff = date.timeIntervalSince(Date())
    guard diff > 0 else { return "Now!" }
    let h = Int(diff / 3600)
    let m = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)
    if h == 0 { return "\(m)m" }
    if m == 0 { return "\(h)h" }
    return "\(h)h \(m)m"
}

// ✅ FIXED — never includes AM/PM in string, always separate
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
                }
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(orangeLine)
                    .frame(width: 1)
                    .padding(.vertical, 12)

                VStack(alignment: .trailing, spacing: 10) {
                    Text(dayLabel(d))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(orangeDim, in: Capsule())

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(orange.opacity(0.7))
                        Text(timeLeft(d))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(textPri)
                        Text("remaining")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(textSec)
                    }
                }
                .padding(.trailing, 16)
                .padding(.vertical, 14)
                .frame(width: 100, alignment: .trailing)
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
                .padding(.bottom, 20)

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
                .padding(.bottom, 12)

                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13))
                        .foregroundStyle(orange)
                    Text(dayLabel(d))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(orange)
                }
                .padding(.bottom, 10)

                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(textSec)
                    Text(entry.alarmLabel)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(textPri)
                        .lineLimit(1)
                }
                .padding(.bottom, 20)

                Rectangle()
                    .fill(orangeLine)
                    .frame(height: 1)
                    .padding(.bottom, 16)

                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(orangeDim)
                            .frame(width: 44, height: 44)
                        Image(systemName: "clock.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(orange)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Time remaining")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(textSec)
                        Text(timeLeft(d))
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(textPri)
                    }
                    Spacer()
                }
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

// MARK: - COUNTDOWN Widget
struct CountdownView: View {
    let entry: FutureAlarmEntry

    var body: some View {
        if let d = entry.alarmDate, !isAlarmPast(d) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(orangeDim)
                        .frame(width: 38, height: 38)
                    Image(systemName: "timer")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(orange)
                }
                Text(timeLeft(d))
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(textPri)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("until alarm")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(textSec)
                Text(entry.alarmLabel)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(orange.opacity(0.8))
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(bg, for: .widget)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 24))
                    .foregroundStyle(orange.opacity(0.4))
                Text("Set New\nAlarm")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(textSec)
                    .multilineTextAlignment(.center)
                Text("Tap to set")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(textSec.opacity(0.5))
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(bg, for: .widget)
        }
    }
}

// MARK: - TIME ONLY Widget
struct TimeOnlyView: View {
    let entry: FutureAlarmEntry

    var body: some View {
        if let d = entry.alarmDate, !isAlarmPast(d) {
            VStack(spacing: 2) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(orange)
                    .padding(.bottom, 4)
                Text(timeString(d, use24Hour: entry.use24Hour))
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(textPri)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if !entry.use24Hour {
                    Text(ampm(d))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(orange)
                        .padding(.top, 1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(bg, for: .widget)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(orange.opacity(0.4))
                Text("--:--")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(textSec.opacity(0.4))
                Text("Set alarm")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(textSec.opacity(0.4))
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(bg, for: .widget)
        }
    }
}

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
            VStack(alignment: .leading, spacing: 3) {
                ForEach(0..<min(entry.upcomingAlarms.count, 3), id: \.self) { i in
                    let alarm = entry.upcomingAlarms[i]
                    HStack(spacing: 0) {
                        Text(entry.use24Hour
                             ? timeString(alarm.date, use24Hour: true)
                             : "\(timeString(alarm.date, use24Hour: false)) \(ampm(alarm.date))")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                            .fixedSize()
                            .widgetAccentable()

                        Spacer()

                        Text(shortDay(alarm.date))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            .containerBackground(.clear, for: .widget)
        }
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

struct CountdownWidget: Widget {
    let kind = "CountdownWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FutureAlarmProvider()) { entry in
            CountdownView(entry: entry)
        }
        .configurationDisplayName("Alarm Countdown")
        .description("Time remaining until your next alarm.")
        .supportedFamilies([.systemSmall])
    }
}

struct TimeOnlyWidget: Widget {
    let kind = "TimeOnlyWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FutureAlarmProvider()) { entry in
            TimeOnlyView(entry: entry)
        }
        .configurationDisplayName("Alarm Time")
        .description("Shows only your next alarm time.")
        .supportedFamilies([.systemSmall])
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
    FutureAlarmEntry(date: .now, alarmDate: Date().addingTimeInterval(8.5 * 3600), alarmLabel: "Morning Coffee", upcomingAlarms: [], use24Hour: false)
}

#Preview("Medium", as: .systemMedium) {
    FutureAlarmWidget()
} timeline: {
    FutureAlarmEntry(date: .now, alarmDate: Date().addingTimeInterval(8.5 * 3600), alarmLabel: "Morning Coffee", upcomingAlarms: [], use24Hour: false)
}

#Preview("Large", as: .systemLarge) {
    FutureAlarmWidget()
} timeline: {
    FutureAlarmEntry(date: .now, alarmDate: Date().addingTimeInterval(8.5 * 3600), alarmLabel: "Morning Coffee", upcomingAlarms: [], use24Hour: false)
}

#Preview("Countdown", as: .systemSmall) {
    CountdownWidget()
} timeline: {
    FutureAlarmEntry(date: .now, alarmDate: Date().addingTimeInterval(8.5 * 3600), alarmLabel: "Morning Coffee", upcomingAlarms: [], use24Hour: false)
}

#Preview("Time Only", as: .systemSmall) {
    TimeOnlyWidget()
} timeline: {
    FutureAlarmEntry(date: .now, alarmDate: Date().addingTimeInterval(8.5 * 3600), alarmLabel: "Morning Coffee", upcomingAlarms: [], use24Hour: false)
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
