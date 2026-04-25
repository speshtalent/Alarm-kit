import SwiftUI


struct CalendarView: View {
    @StateObject private var alarmService = AlarmService.shared
    @State private var selectedDate: Date = Date()
    @State private var currentMonth: Date = Date()
    @State private var showAddAlarm = false
    @State private var viewMode: ViewMode = .monthly
    @State private var editingItem: AlarmService.AlarmListItem? = nil
    @State private var showPastDateAlert = false
    
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
        var dates = Set<String>()
        
        for item in alarmService.alarms {
            guard let fireDate = item.fireDate else { continue }
            let groupID = alarmService.getGroupID(for: item.id) ?? item.id
            let repeatDays = alarmService.getRepeatDays(forGroup: groupID)
            let hasWeekDays = repeatDays.contains { $0 >= 1 && $0 <= 7 } && !repeatDays.contains { $0 >= 8 && $0 <= 31 } && !repeatDays.contains { $0 >= 101 }
            let hasMonths = repeatDays.contains { $0 >= 101 && $0 <= 112 }
            let dayValues = repeatDays.filter { $0 >= 1 && $0 <= 31 }

            if hasWeekDays {
                // ✅ Add dot for every day in current month that matches weekday
                guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) else { continue }
                let daysCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
                for dayOffset in 0..<daysCount {
                    if let date = calendar.date(byAdding: .day, value: dayOffset, to: monthStart) {
                        let weekday = calendar.component(.weekday, from: date)
                        if repeatDays.contains(weekday) {
                            dates.insert(formatter.string(from: date))
                        }
                    }
                }
            } else if hasMonths || repeatDays.contains(100) {
                // ✅ Add dot for matching day in selected months
                let currentMonthValue = 100 + calendar.component(.month, from: currentMonth)
                let monthMatches = hasMonths ? repeatDays.contains(currentMonthValue) : true
                if monthMatches, let dayOfMonth = dayValues.first {
                    var comps = calendar.dateComponents([.year, .month], from: currentMonth)
                    comps.day = dayOfMonth
                    if let matchDate = calendar.date(from: comps) {
                        dates.insert(formatter.string(from: matchDate))
                    }
                }
            } else if !dayValues.isEmpty && !hasWeekDays && !repeatDays.contains(where: { $0 >= 2025 }) {
                // ✅ Every month — only day selected, no months, no years
                if let dayOfMonth = dayValues.first {
                    var comps = calendar.dateComponents([.year, .month], from: currentMonth)
                    comps.day = dayOfMonth
                    if let matchDate = calendar.date(from: comps) {
                        dates.insert(formatter.string(from: matchDate))
                    }
                }
            } else if repeatDays.contains(where: { $0 >= 2025 }) {
                // ✅ Yearly — add dot for matching year + month + day
                let currentYear = calendar.component(.year, from: currentMonth)
                let currentMonthNum = calendar.component(.month, from: currentMonth)
                let months = repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted()
                let years = repeatDays.filter { $0 >= 2025 }.sorted()
                if years.contains(currentYear) {
                    if let dayOfMonth = dayValues.first {
                        if months.isEmpty {
                            // ✅ No month specified — use fireDate's month
                            let fireMonth = calendar.component(.month, from: fireDate)
                            if fireMonth == currentMonthNum {
                                var comps = DateComponents()
                                comps.year = currentYear
                                comps.month = currentMonthNum
                                comps.day = dayOfMonth
                                if let matchDate = calendar.date(from: comps) {
                                    dates.insert(formatter.string(from: matchDate))
                                }
                            }
                        } else if months.contains(100 + currentMonthNum) {
                            var comps = DateComponents()
                            comps.year = currentYear
                            comps.month = currentMonthNum
                            comps.day = dayOfMonth
                            if let matchDate = calendar.date(from: comps) {
                                dates.insert(formatter.string(from: matchDate))
                            }
                        }
                    }
                }
            } else {
                // ✅ One-time or exact date
                dates.insert(formatter.string(from: fireDate))
            }
        }
        return dates
    }
    
    private var alarmsForSelectedDate: [AlarmService.AlarmListItem] {
        var seenGroupIDs = Set<UUID>()
        return alarmService.alarms.filter { item in
            guard let date = item.fireDate else { return false }
            
            let groupID = alarmService.getGroupID(for: item.id) ?? item.id
            let repeatDays = alarmService.getRepeatDays(forGroup: groupID)
            let hasWeekDays = repeatDays.contains { $0 >= 1 && $0 <= 7 } && !repeatDays.contains { $0 >= 8 && $0 <= 31 } && !repeatDays.contains { $0 >= 101 }
            let hasMonths = repeatDays.contains { $0 >= 101 && $0 <= 112 }
            let dayValues = repeatDays.filter { $0 >= 1 && $0 <= 31 }
            let selectedDay = calendar.component(.day, from: selectedDate)
            let selectedMonth = calendar.component(.month, from: selectedDate)
            let selectedWeekday = calendar.component(.weekday, from: selectedDate)
            
            var matches = false
            
            // ✅ Exact date match
            if calendar.isDate(date, inSameDayAs: selectedDate) {
                matches = true
            }
            // ✅ Weekly repeat
            else if hasWeekDays && repeatDays.contains(selectedWeekday) {
                matches = true
            }
            // ✅ Monthly with selected months
            else if hasMonths {
                let monthValue = 100 + selectedMonth
                if repeatDays.contains(monthValue) && dayValues.contains(selectedDay) {
                    matches = true
                }
            }
            // ✅ Monthly generic
            else if repeatDays.contains(100) && dayValues.contains(selectedDay) {
                matches = true
            }
            // ✅ Yearly
            else if repeatDays.contains(where: { $0 >= 2025 }) {
                let selectedYear = calendar.component(.year, from: selectedDate)
                if repeatDays.contains(selectedYear) &&
                    calendar.component(.day, from: date) == selectedDay &&
                    calendar.component(.month, from: date) == selectedMonth {
                    matches = true
                }
            }
            
            if matches {
                // ✅ Only show one alarm per group
                if seenGroupIDs.contains(groupID) { return false }
                seenGroupIDs.insert(groupID)
                return true
            }
            return false
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
    
    private var daysInWeek: [Date] {
        let weekday = calendar.component(.weekday, from: selectedDate) - 1
        guard let weekStart = calendar.date(byAdding: .day, value: -weekday, to: selectedDate) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }
    
    private var hoursOfDay: [Date] {
        guard let dayStart = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: selectedDate)) else { return [] }
        return (0..<24).compactMap { calendar.date(byAdding: .hour, value: $0, to: dayStart) }
    }
    
    private func alarmsForHour(_ hour: Date) -> [AlarmService.AlarmListItem] {
        alarmService.alarms.filter { item in
            guard let date = item.fireDate else { return false }
            return calendar.isDate(date, inSameDayAs: selectedDate) &&
            calendar.component(.hour, from: date) == calendar.component(.hour, from: hour)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color("AppBackground").ignoresSafeArea()
                
                VStack(spacing: 0) {
                // MARK: Header
                HStack {
                    Text("Calendar")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("PrimaryText"))
                    Spacer()
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
                
                // MARK: Segment
                HStack(spacing: 0) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.spring(response: 0.3)) { viewMode = mode }
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(viewMode == mode ? .black : Color("SecondaryText"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(viewMode == mode ? Color.orange : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 11))
                        }
                    }
                }
                .padding(4)
                .background(Color("CardBackground"))
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                
                    switch viewMode {
                    case .monthly: monthlyView
                    case .weekly:  weeklyView
                    case .daily:   dailyView
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            alarmService.loadAlarms()
        }
        .navigationDestination(isPresented: $showAddAlarm) {
            AddAlarmView(preselectedDate: selectedDate, hideDateToggle: viewMode == .daily) { date, title, snoozeEnabled, snoozeDuration, sound, repeatDays, calendarEnabled in
                Task {
                    _ = await alarmService.scheduleFutureAlarm(
                        date: date,
                        title: title,
                        snoozeEnabled: snoozeEnabled,
                        snoozeDuration: snoozeDuration,
                        sound: sound,
                        repeatDays: repeatDays,
                        calendarEnabled: calendarEnabled
                    )
                    await MainActor.run { alarmService.loadAlarms() }
                }
            }
        }
        .alert("Date Already Passed", isPresented: $showPastDateAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please select a future date to add an alarm.")
        }
        .navigationDestination(item: $editingItem) { item in
            let groupID = alarmService.getGroupID(for: item.id) ?? item.id
            let groupRepeatDays = alarmService.getRepeatDays(forGroup: groupID)
            AddAlarmView(editingItem: item, repeatDaysToLoad: groupRepeatDays) { date, title, snoozeEnabled, snoozeDuration, sound, repeatDays, calendarEnabled in
                Task {
                    alarmService.cancelAlarm(id: item.id)
                    _ = await alarmService.scheduleFutureAlarm(
                        date: date,
                        title: title,
                        snoozeEnabled: snoozeEnabled,
                        snoozeDuration: snoozeDuration,
                        sound: sound,
                        repeatDays: repeatDays,
                        calendarEnabled: calendarEnabled
                    )
                    await MainActor.run { alarmService.loadAlarms() }
                }
            }
        }
    }
    
    // MARK: - Monthly View
    var monthlyView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Year navigation
                HStack {
                    Button {
                        withAnimation {
                            currentMonth = calendar.date(byAdding: .year, value: -1, to: currentMonth) ?? currentMonth
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.orange)
                            .font(.system(size: 18, weight: .semibold))
                    }
                    Spacer()
                    Text(currentMonth.formatted(.dateTime.year()))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("PrimaryText"))
                    Spacer()
                    Button {
                        withAnimation {
                            currentMonth = calendar.date(byAdding: .year, value: 1, to: currentMonth) ?? currentMonth
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.orange)
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                
                // Month navigation
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
                    Text(currentMonth.formatted(.dateTime.month(.wide)))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("PrimaryText"))
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
                HStack(spacing: 0) {
                    ForEach(weekdays, id: \.self) { day in
                        Text(day)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color("SecondaryText"))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                
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
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            let horizontal = abs(value.translation.width)
                            let vertical = abs(value.translation.height)
                            guard horizontal > vertical else { return }
                            if value.translation.width < -50 {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } else if value.translation.width > 50 {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                )
                
                HStack {
                    Text(selectedDate.formatted(.dateTime.weekday(.wide).month().day()))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("PrimaryText"))
                    Spacer()
                    Button {
                        if calendar.startOfDay(for: selectedDate) < calendar.startOfDay(for: Date()) {
                            showPastDateAlert = true
                        } else {
                            showAddAlarm = true
                        }
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
                .padding(.bottom, 8)
                
                if alarmsForSelectedDate.isEmpty {
                    Text("No alarms on this day")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color("SecondaryText"))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                } else {
                    List {
                        ForEach(alarmsForSelectedDate) { item in
                            calendarAlarmRow(item: item)
                                .listRowBackground(Color("AppBackground"))
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(height: CGFloat(alarmsForSelectedDate.count) * 110)
                    .padding(.bottom, 20)
                }
            }
        }
    }
    
    // MARK: - Weekly View
    var weeklyView: some View {
        ScrollView {
            VStack(spacing: 0) {
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
                        .foregroundStyle(Color("PrimaryText"))
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
                                    .foregroundStyle(isSelected ? .orange : Color("SecondaryText"))
                                Text("\(calendar.component(.day, from: date))")
                                    .font(.system(size: 14, weight: isToday ? .bold : .medium, design: .rounded))
                                    .foregroundStyle(isSelected ? .black : isToday ? .orange : Color("PrimaryText"))
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
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            let horizontal = abs(value.translation.width)
                            let vertical = abs(value.translation.height)
                            guard horizontal > vertical else { return }
                            if value.translation.width < -50 {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    selectedDate = calendar.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } else if value.translation.width > 50 {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    selectedDate = calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                )
                
                Divider().padding(.bottom, 8)
                
                HStack {
                    Text(selectedDate.formatted(.dateTime.weekday(.wide).month().day()))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("PrimaryText"))
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
                .padding(.bottom, 8)
                
                if alarmsForSelectedDate.isEmpty {
                    Text("No alarms this day")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color("SecondaryText"))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                } else {
                    List {
                        ForEach(alarmsForSelectedDate) { item in
                            calendarAlarmRow(item: item)
                                .listRowBackground(Color("AppBackground"))
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(height: CGFloat(alarmsForSelectedDate.count) * 100)
                    .padding(.bottom, 20)
                }
            }
        }
    }
    
    // MARK: - Daily View
    var dailyView: some View {
        VStack(spacing: 0) {
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
                    .foregroundStyle(Color("PrimaryText"))
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
            .padding(.bottom, 8)
            
            List {
                ForEach(hoursOfDay, id: \.self) { hour in
                    let hourAlarms = alarmsForHour(hour)
                    HStack(alignment: .top, spacing: 12) {
                        Text(hour.formatted(.dateTime.hour()))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color("SecondaryText"))
                            .frame(width: 50, alignment: .trailing)
                            .padding(.top, 10)
                        
                        VStack(spacing: 0) {
                            Divider().padding(.top, 14)
                            Spacer()
                        }
                        .frame(width: 1, height: hourAlarms.isEmpty ? 44 : CGFloat(44 + hourAlarms.count * 64))
                        
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
                    .listRowBackground(Color("AppBackground"))
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
    
    private var weekRangeTitle: String {
        let days = daysInWeek
        guard let first = days.first, let last = days.last else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return "\(f.string(from: first)) – \(f.string(from: last))"
    }
    
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
        
        let isFutureYear = calendar.component(.year, from: currentMonth) > calendar.component(.year, from: Date())
        let isPast = !isFutureYear && date < calendar.startOfDay(for: Date())

        Button {
            withAnimation(.spring(response: 0.3)) {
                selectedDate = date
            }
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 16, weight: isToday ? .bold : .medium, design: .rounded))
                    .foregroundStyle(
                        isPast ? Color("SecondaryText").opacity(0.3) :
                        isSelected ? .black :
                        isToday ? .orange : Color("PrimaryText")
                    )
                    .frame(width: 32, height: 32)
                    .background(isSelected ? Color.orange : Color.clear)
                    .clipShape(Circle())
                Circle()
                    .fill(hasAlarm ? Color.orange : Color.clear)
                    .frame(width: 4, height: 4)
            }
        }
    }
    
    @ViewBuilder
    func calendarAlarmRow(item: AlarmService.AlarmListItem) -> some View {
        VStack(spacing: 0) {
            // ✅ Orange header
            HStack {
                Text(item.label.isEmpty ? "Alarm" : item.label)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(item.isEnabled ? .black : Color("SecondaryText"))
                Spacer()
                Text(item.fireDate.flatMap {
                    let f = DateFormatter()
                    f.dateFormat = "EEE, MMM d"
                    return f.string(from: $0)
                } ?? "")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(item.isEnabled ? Color.black.opacity(0.6) : Color("SecondaryText"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(item.isEnabled ? Color.orange : Color("AppBackground"))
            
            // ✅ Time + toggle
            HStack(spacing: 12) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(item.fireDate.flatMap {
                        let f = DateFormatter()
                        f.dateFormat = "h:mm"
                        return f.string(from: $0)
                    } ?? "--:--")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color("PrimaryText"))
                    Text(item.fireDate.flatMap {
                        let f = DateFormatter()
                        f.amSymbol = "AM"
                        f.pmSymbol = "PM"
                        f.dateFormat = "a"
                        return f.string(from: $0)
                    } ?? "")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(item.isEnabled ? .orange : Color("SecondaryText"))
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { item.isEnabled },
                    set: { _ in
                        alarmService.toggleAlarm(id: item.id)
                        Task {
                            try? await Task.sleep(nanoseconds: 800_000_000)
                            await MainActor.run { alarmService.loadAlarms() }
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                ))
                .tint(.orange)
                .labelsHidden()
            }
            .padding(16)
            .background(Color("CardBackground"))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .opacity(item.isEnabled ? 1.0 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture { editingItem = item }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                alarmService.cancelAlarm(id: item.id)
                alarmService.loadAlarms()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                editingItem = item
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.orange)
        }
    }
}
