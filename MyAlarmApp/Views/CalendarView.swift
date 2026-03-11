import SwiftUI

struct CalendarView: View {
    @StateObject private var alarmService = AlarmService.shared
    @State private var selectedDate: Date = Date()
    @State private var currentMonth: Date = Date()

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    // get all dates that have alarms
    private var alarmDates: Set<String> {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return Set(alarmService.alarms.compactMap { item in
            guard let date = item.fireDate else { return nil }
            return formatter.string(from: date)
        })
    }

    // alarms for selected date
    private var alarmsForSelectedDate: [AlarmService.AlarmListItem] {
        alarmService.alarms.filter { item in
            guard let date = item.fireDate else { return false }
            return calendar.isDate(date, inSameDayAs: selectedDate)
        }
    }

    // all days to show in current month grid
    private var daysInMonth: [Date?] {
        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: currentMonth)
        ) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: monthStart) - 1
        let daysCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30

        var days: [Date?] = Array(repeating: nil, count: firstWeekday)
        for day in 0..<daysCount {
            if let date = calendar.date(byAdding: .day, value: day, to: monthStart) {
                days.append(date)
            }
        }
        return days
    }

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.09)
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // MARK: Header
                HStack {
                    Text("Calendar")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)

                // MARK: Month Navigation
                HStack {
                    Button {
                        withAnimation {
                            currentMonth = calendar.date(
                                byAdding: .month, value: -1, to: currentMonth
                            ) ?? currentMonth
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.orange)
                            .font(.system(size: 18, weight: .semibold))
                    }

                    Spacer()

                    Text(currentMonth.formatted(.dateTime.month(.wide).year()))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        withAnimation {
                            currentMonth = calendar.date(
                                byAdding: .month, value: 1, to: currentMonth
                            ) ?? currentMonth
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.orange)
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                // MARK: Weekday Headers
                HStack(spacing: 0) {
                    ForEach(weekdays, id: \.self) { day in
                        Text(day)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                // MARK: Calendar Grid
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(0..<daysInMonth.count, id: \.self) { index in
                        if let date = daysInMonth[index] {
                            dayCell(date: date)
                        } else {
                            Color.clear.frame(height: 44)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)

                // MARK: Alarms for selected date
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(selectedDate.formatted(.dateTime.weekday(.wide).month().day()))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(alarmsForSelectedDate.count) alarm\(alarmsForSelectedDate.count == 1 ? "" : "s")")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.gray)
                    }
                    .padding(.horizontal, 20)

                    if alarmsForSelectedDate.isEmpty {
                        Text("No alarms on this day")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(alarmsForSelectedDate) { item in
                                    calendarAlarmRow(item: item)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                Spacer()
            }
        }
        .onAppear {
            alarmService.loadAlarms()
        }
    }

    // MARK: Day Cell
    @ViewBuilder
    func dayCell(date: Date) -> some View {
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f
        }()
        let dateString = formatter.string(from: date)
        let hasAlarm = alarmDates.contains(dateString)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)

        Button {
            withAnimation(.spring(response: 0.3)) {
                selectedDate = date
            }
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 16, weight: isToday ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? .black : isToday ? .orange : .white)
                    .frame(width: 36, height: 36)
                    .background(isSelected ? Color.orange : Color.clear)
                    .clipShape(Circle())

                // orange dot if alarm exists on this day
                Circle()
                    .fill(hasAlarm ? Color.orange : Color.clear)
                    .frame(width: 5, height: 5)
            }
        }
    }

    // MARK: Alarm Row in Calendar
    // shows alarm name and time — no add to calendar button
    // user adds to calendar from AddAlarmView when setting the alarm
    @ViewBuilder
    func calendarAlarmRow(item: AlarmService.AlarmListItem) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "alarm")
                    .foregroundStyle(.orange)
                    .font(.system(size: 18))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.label)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(item.fireDate?.formatted(
                    Date.FormatStyle()
                        .hour(.defaultDigits(amPM: .abbreviated))
                        .minute(.twoDigits)
                ) ?? "")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.gray)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(white: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
