import SwiftUI

struct CalendarView: View {
    @StateObject private var alarmService = AlarmService.shared
    @State private var selectedDate: Date = Date()
    @State private var currentMonth: Date = Date()
    @State private var showAddAlarm = false
    // ✅ ADDED — view mode switcher
    @State private var viewMode: ViewMode = .monthly

    // ✅ ADDED — view modes
    enum ViewMode: String, CaseIterable {
        case daily = "Day"
        case weekly = "Week"
        case monthly = "Month"
    }

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    private let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private var alarmDates: Set<String> {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return Set(alarmService.alarms.compactMap { item in
            guard let date = item.fireDate else { return nil }
            return formatter.string(from: date)
        })
    }

    private var alarmsForSelectedDate: [AlarmService.AlarmListItem] {
        alarmService.alarms.filter { item in
            guard let date = item.fireDate else { return false }
            return calendar.isDate(date, inSameDayAs: selectedDate)
        }
    }

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

    // ✅ ADDED — days for weekly view (7 days from start of selected week)
    private var daysInWeek: [Date] {
        let weekday = calendar.component(.weekday, from: selectedDate) - 1
        guard let weekStart = calendar.date(byAdding: .day, value: -weekday, to: selectedDate) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    // ✅ ADDED — hourly slots for daily view
    private var hoursOfDay: [Date] {
        guard let dayStart = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: selectedDate)) else { return [] }
        return (0..<24).compactMap { calendar.date(byAdding: .hour, value: $0, to: dayStart) }
    }

    // ✅ ADDED — alarms for a specific hour slot
    private func alarmsForHour(_ hour: Date) -> [AlarmService.AlarmListItem] {
        alarmService.alarms.filter { item in
            guard let date = item.fireDate else { return false }
            return calendar.isDate(date, inSameDayAs: selectedDate) &&
                   calendar.component(.hour, from: date) == calendar.component(.hour, from: hour)
        }
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
                    // ✅ ADDED — Add alarm button in header
                    Button {
                        showAddAlarm = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 36, height: 36)
                            .background(.orange)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // ✅ ADDED — View mode switcher (Day / Week / Month)
                HStack(spacing: 0) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.spring(response: 0.3)) { viewMode = mode }
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(viewMode == mode ? .black : .gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(viewMode == mode ? Color.orange : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 11))
                        }
                    }
                }
                .padding(4)
                .background(Color(white: 0.15))
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                // ✅ UPDATED — swipe left/right to switch between Day/Week/Month
                Group {
                    switch viewMode {
                    case .monthly: monthlyView
                    case .weekly:  weeklyView
                    case .daily:   dailyView
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 50)
                        .onEnded { value in
                            if value.translation.width < -50 {
                                // ✅ swipe left → next mode
                                withAnimation(.spring(response: 0.3)) {
                                    switch viewMode {
                                    case .daily: viewMode = .weekly
                                    case .weekly: viewMode = .monthly
                                    case .monthly: viewMode = .daily
                                    }
                                }
                            } else if value.translation.width > 50 {
                                // ✅ swipe right → previous mode
                                withAnimation(.spring(response: 0.3)) {
                                    switch viewMode {
                                    case .daily: viewMode = .monthly
                                    case .weekly: viewMode = .daily
                                    case .monthly: viewMode = .weekly
                                    }
                                }
                            }
                        }
                )
            }
        }
        .onAppear {
            alarmService.loadAlarms()
        }
        // ✅ ADDED — sheet to add alarm for selected date
        .sheet(isPresented: $showAddAlarm, onDismiss: {
            alarmService.loadAlarms()
        }) {
            AddAlarmView(preselectedDate: selectedDate) { date, title, snoozeEnabled, snoozeDuration, sound in
                Task {
                    _ = await alarmService.scheduleFutureAlarm(
                        date: date,
                        title: title,
                        snoozeEnabled: snoozeEnabled,
                        snoozeDuration: snoozeDuration,
                        sound: sound
                    )
                    await MainActor.run { alarmService.loadAlarms() }
                }
            }
        }
    }

    // MARK: - Monthly View (existing, unchanged)
    var monthlyView: some View {
        VStack(spacing: 0) {
            // Month Navigation
            HStack {
                Button {
                    withAnimation {
                        currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
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
                        currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.orange)
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Weekday Headers
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

            // Calendar Grid
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

            // Alarms for selected date + Add button
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(selectedDate.formatted(.dateTime.weekday(.wide).month().day()))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    // ✅ ADDED — add alarm for selected date
                    Button {
                        showAddAlarm = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Add Alarm")
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
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

    // ✅ ADDED — Weekly View
    var weeklyView: some View {
        VStack(spacing: 0) {
            // Week navigation
            HStack {
                Button {
                    withAnimation {
                        selectedDate = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.orange)
                        .font(.system(size: 18, weight: .semibold))
                }
                Spacer()
                Text(weekRangeTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    withAnimation {
                        selectedDate = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.orange)
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Days of week row
            HStack(spacing: 0) {
                ForEach(daysInWeek, id: \.self) { date in
                    let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                    let isToday = calendar.isDateInToday(date)
                    let formatter: DateFormatter = {
                        let f = DateFormatter()
                        f.dateFormat = "yyyy-MM-dd"
                        return f
                    }()
                    let hasAlarm = alarmDates.contains(formatter.string(from: date))

                    Button {
                        withAnimation(.spring(response: 0.3)) { selectedDate = date }
                    } label: {
                        VStack(spacing: 4) {
                            Text(date.formatted(.dateTime.weekday(.narrow)))
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(isSelected ? .orange : .gray)
                            Text("\(calendar.component(.day, from: date))")
                                .font(.system(size: 16, weight: isToday ? .bold : .medium, design: .rounded))
                                .foregroundStyle(isSelected ? .black : isToday ? .orange : .white)
                                .frame(width: 34, height: 34)
                                .background(isSelected ? Color.orange : Color.clear)
                                .clipShape(Circle())
                            Circle()
                                .fill(hasAlarm ? Color.orange : Color.clear)
                                .frame(width: 5, height: 5)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.bottom, 16)

            // Alarms for selected day + Add button
            HStack {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    showAddAlarm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add Alarm")
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            if alarmsForSelectedDate.isEmpty {
                Text("No alarms this day")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
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
            Spacer()
        }
    }

    // ✅ ADDED — Daily View with hourly timeline
    var dailyView: some View {
        VStack(spacing: 0) {
            // Day navigation
            HStack {
                Button {
                    withAnimation {
                        selectedDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.orange)
                        .font(.system(size: 18, weight: .semibold))
                }
                Spacer()
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month().day().year()))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    withAnimation {
                        selectedDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.orange)
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // Add alarm for this day
            HStack {
                Spacer()
                Button {
                    showAddAlarm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add Alarm")
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Hourly timeline
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(hoursOfDay, id: \.self) { hour in
                        let hourAlarms = alarmsForHour(hour)
                        HStack(alignment: .top, spacing: 12) {
                            // Hour label
                            Text(hour.formatted(.dateTime.hour()))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.gray)
                                .frame(width: 50, alignment: .trailing)
                                .padding(.top, 10)

                            // Divider line
                            VStack(spacing: 0) {
                                Divider()
                                    .background(Color.white.opacity(0.08))
                                    .padding(.top, 14)
                                Spacer()
                            }
                            .frame(width: 1, height: hourAlarms.isEmpty ? 44 : CGFloat(44 + hourAlarms.count * 64))

                            // Alarms in this hour slot
                            VStack(spacing: 6) {
                                if hourAlarms.isEmpty {
                                    Color.clear.frame(height: 44)
                                } else {
                                    ForEach(hourAlarms) { item in
                                        calendarAlarmRow(item: item)
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }

    // ✅ ADDED — helper for week range title
    private var weekRangeTitle: String {
        let days = daysInWeek
        guard let first = days.first, let last = days.last else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(f.string(from: first)) – \(f.string(from: last))"
    }

    // MARK: Day Cell (unchanged)
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
                Circle()
                    .fill(hasAlarm ? Color.orange : Color.clear)
                    .frame(width: 5, height: 5)
            }
        }
    }

    // MARK: Alarm Row (unchanged)
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
