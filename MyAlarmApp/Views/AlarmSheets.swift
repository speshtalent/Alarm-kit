import SwiftUI

// MARK: - Schedule for Future Sheet
struct ScheduleForFutureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date?
    @Binding var repeatType: String
    @Binding var repeatDays: Set<Int>
    @Binding var selectedHour: Int
    @Binding var selectedMinute: Int
    @Binding var selectedAMPM: Int
    var isEditing: Bool = false
    @AppStorage("use24HourFormat") private var use24HourFormat: Bool = false
    
    
    @State private var selectedTab: Int = 0
    @State private var showHourPicker: Bool = false
    @State private var showMinutePicker: Bool = false
    @State private var originalDate: Date? = nil
    @State private var originalRepeatDays: Set<Int> = []
    @State private var originalRepeatType: String = ""
    @State private var originalHour: Int = 0
    @State private var originalMinute: Int = 0
    @State private var originalAMPM: Int = 0
    private var hasSheetChanges: Bool {
        // ✅ Common time check
        let timeChanged = selectedHour != originalHour ||
        selectedMinute != originalMinute ||
        selectedAMPM != originalAMPM
        
        if selectedTab == 1 {
            // ✅ Monthly — build full result and compare
            var result: Set<Int> = monthlyMonths
            if monthlyDay > 0 { result.insert(monthlyDay) }
            switch monthlyRepeatMode {
            case "forever": result.insert(100)
            case "once": result.insert(200)
            case "stopafter": result.insert(200 + monthlyStopAfterYears)
            default: result.insert(200)
            }
            return result != originalRepeatDays ||
            repeatType != originalRepeatType ||
            timeChanged
        }
        
        if selectedTab == 2 {
            // ✅ Yearly — check date, repeatOn, repeatCount
            let originalYearCount = originalRepeatDays.filter { $0 >= 2025 }.count
            let originalRepeatOn = originalYearCount > 0
            return yearlyDate != originalDate ||
            yearlyRepeatOn != originalRepeatOn ||
            (yearlyRepeatOn && yearlyRepeatCount != max(originalYearCount, 1)) ||
            repeatType != originalRepeatType ||
            timeChanged ||
            selectedTab != (originalRepeatType == "yearly" ? 2 : selectedTab)
        }
        
        // ✅ One time
        return selectedDate != originalDate ||
        repeatType != originalRepeatType ||
        timeChanged
    }
    @State private var monthlyDay: Int = 0
    @State private var monthlyMonths: Set<Int> = []
    @State private var monthlyRepeatMode: String = "once"
    @State private var monthlyStopAfterYears: Int = 2
    @State private var yearlyDate: Date? = nil
    @State private var showNoDayAlert: Bool = false
    @State private var yearlyRepeatOn: Bool = false
    @State private var yearlyRepeatCount: Int = 5
    
    var body: some View {
        ZStack {
            Color("AppBackground").ignoresSafeArea()
            VStack(spacing: 0) {
                
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color("SecondaryText").opacity(0.4))
                    .frame(width: 40, height: 5)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                
                Text("Schedule for Future")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color("PrimaryText"))
                    .padding(.bottom, 12)
                
                // Time display compact
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Spacer()
                        VStack(spacing: 2) {
                            Text("HR")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Color("SecondaryText"))
                                .tracking(2)
                            Text(use24HourFormat ? String(format: "%02d", selectedHour) : String(format: "%d", selectedHour))
                                .font(.system(size: 64, weight: .heavy, design: .rounded))
                                .foregroundStyle(showHourPicker ? .orange : Color("PrimaryText"))
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.3), value: selectedHour)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3)) {
                                        showHourPicker.toggle()
                                        showMinutePicker = false
                                    }
                                }
                        }
                        Text(":")
                            .font(.system(size: 48, weight: .heavy, design: .rounded))
                            .foregroundStyle(.orange)
                            .padding(.bottom, 16)
                        VStack(spacing: 2) {
                            Text("MIN")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Color("SecondaryText"))
                                .tracking(2)
                            Text(String(format: "%02d", selectedMinute))
                                .font(.system(size: 64, weight: .heavy, design: .rounded))
                                .foregroundStyle(showMinutePicker ? .orange : Color("PrimaryText"))
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.3), value: selectedMinute)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3)) {
                                        showMinutePicker.toggle()
                                        showHourPicker = false
                                    }
                                }
                        }
                        if !use24HourFormat {
                            VStack(spacing: 6) {
                                Button {
                                    withAnimation(.spring(response: 0.3)) { selectedAMPM = 0 }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Text("AM")
                                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                                        .foregroundStyle(selectedAMPM == 0 ? .black : Color("SecondaryText"))
                                        .frame(width: 52, height: 36)
                                        .background(selectedAMPM == 0 ? Color.orange : Color("AppBackground"))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                Button {
                                    withAnimation(.spring(response: 0.3)) { selectedAMPM = 1 }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Text("PM")
                                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                                        .foregroundStyle(selectedAMPM == 1 ? .black : Color("SecondaryText"))
                                        .frame(width: 52, height: 36)
                                        .background(selectedAMPM == 1 ? Color.orange : Color("AppBackground"))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            .padding(.bottom, 16)
                            .padding(.leading, 6)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    
                    if showHourPicker {
                        Picker("Hour", selection: $selectedHour) {
                            if use24HourFormat {
                                ForEach(0...23, id: \.self) { h in
                                    Text(String(format: "%02d", h)).tag(h)
                                }
                            } else {
                                ForEach(1...12, id: \.self) { h in
                                    Text(String(format: "%d", h)).tag(h)
                                }
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 100)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    if showMinutePicker {
                        Picker("Minute", selection: $selectedMinute) {
                            ForEach(0...59, id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 100)
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 12)
                .animation(.spring(response: 0.3), value: showHourPicker)
                .animation(.spring(response: 0.3), value: showMinutePicker)
                
                
                // Tabs
                HStack(spacing: 0) {
                    ForEach(["One time", "Monthly", "Yearly"], id: \.self) { tab in
                        let index = ["One time", "Monthly", "Yearly"].firstIndex(of: tab) ?? 0
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                selectedTab = index
                            }
                        } label: {
                            Text(tab)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(selectedTab == index ? .black : Color("SecondaryText"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(selectedTab == index ? Color.orange : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(4)
                .background(Color("CardBackground"))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                
                // Content
                ScrollView {
                    if selectedTab == 0 {
                        OneTimeTabView(selectedDate: $selectedDate, timeStr: {
                            let h = use24HourFormat ? String(format: "%02d", selectedHour) : String(format: "%d", selectedHour)
                            let m = String(format: "%02d", selectedMinute)
                            let ampm = use24HourFormat ? "" : (selectedAMPM == 0 ? " AM" : " PM")
                            return "\(h):\(m)\(ampm)"
                        }())
                    } else if selectedTab == 1 {
                        MonthlyTabView(
                            repeatDays: $repeatDays,
                            repeatType: $repeatType,
                            selectedDay: $monthlyDay,
                            selectedMonths: $monthlyMonths,
                            repeatMode: $monthlyRepeatMode,
                            stopAfterYears: $monthlyStopAfterYears,
                            timeStr: {
                                let h = use24HourFormat ? String(format: "%02d", selectedHour) : String(format: "%d", selectedHour)
                                let m = String(format: "%02d", selectedMinute)
                                let ampm = use24HourFormat ? "" : (selectedAMPM == 0 ? " AM" : " PM")
                                return "\(h):\(m)\(ampm)"
                            }()
                        )
                    } else {
                        YearlyTabView(
                            repeatDays: $repeatDays,
                            repeatType: $repeatType,
                            selectedDate: $yearlyDate,
                            repeatOn: $yearlyRepeatOn,
                            repeatCount: $yearlyRepeatCount,
                            timeStr: {
                                let h = use24HourFormat ? String(format: "%02d", selectedHour) : String(format: "%d", selectedHour)
                                let m = String(format: "%02d", selectedMinute)
                                let ampm = use24HourFormat ? "" : (selectedAMPM == 0 ? " AM" : " PM")
                                return "\(h):\(m)\(ampm)"
                            }()
                        )
                    }
                }
                
                Spacer()
                
                // Done & Cancel
                HStack(spacing: 12) {
                    Button {
                        if selectedTab == 0 {
                            repeatType = ""
                            repeatDays = []
                        } else if selectedTab == 1 {
                            if monthlyDay == 0 {
                                showNoDayAlert = true
                                return
                            }
                            repeatType = "monthly"
                            selectedDate = nil  // ✅ Clear one time date when switching to monthly
                            var result: Set<Int> = monthlyMonths
                            result.insert(monthlyDay)
                            switch monthlyRepeatMode {
                            case "forever": result.insert(100)
                            case "once": result.insert(200)
                            case "stopafter": result.insert(200 + monthlyStopAfterYears)
                            default: result.insert(200)
                            }
                            repeatDays = result
                        } else if selectedTab == 2 {
                            if yearlyDate == nil {
                                showNoDayAlert = true
                                return
                            }
                            repeatType = "yearly"
                            selectedDate = nil
                            if let date = yearlyDate {
                                selectedDate = date
                                var result: Set<Int> = []
                                let cal = Calendar.current
                                let year = cal.component(.year, from: date)
                                let month = cal.component(.month, from: date)
                                let day = cal.component(.day, from: date)
                                result.insert(day)
                                result.insert(100 + month)
                                if yearlyRepeatOn {
                                    let currentMonth = cal.component(.month, from: Date())
                                    let startYear = month > currentMonth ? year : year + 1
                                    for i in 0..<yearlyRepeatCount {
                                        result.insert(startYear + i)
                                    }
                                } else {
                                    // ✅ No repeat — insert current year as default
                                    result.insert(cal.component(.year, from: Date()))
                                }
                                repeatDays = result
                            }
                        }
                        dismiss()
                    } label: {
                        Text(isEditing ? "Update" : "Done")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(isEditing && !hasSheetChanges ? Color("SecondaryText") : .black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(isEditing && !hasSheetChanges ? Color("CardBackground") : Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .disabled(isEditing && !hasSheetChanges)
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color("SecondaryText"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color("CardBackground"))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .alert("Please Select a Day", isPresented: $showNoDayAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Please select a day of the month before continuing.")
                }
                .onAppear {
                    monthlyDay = repeatDays.filter { $0 >= 1 && $0 <= 31 }.first ?? 0
                    monthlyMonths = repeatDays.filter { $0 >= 101 && $0 <= 112 }
                    if repeatDays.contains(100) {
                        monthlyRepeatMode = "forever"
                    } else if let stopFlag = repeatDays.filter({ $0 >= 201 }).first {
                        monthlyRepeatMode = "stopafter"
                        monthlyStopAfterYears = stopFlag - 200
                    } else {
                        monthlyRepeatMode = "once"
                    }
                    // ✅ Load yearly data
                    if repeatType == "yearly" {
                        yearlyDate = selectedDate
                        let years = repeatDays.filter { $0 >= 2025 }
                        if !years.isEmpty {
                            yearlyRepeatOn = true
                            yearlyRepeatCount = years.count
                        }
                    }
                    if repeatType == "monthly" {
                        selectedTab = 1
                    } else if repeatType == "yearly" {
                        selectedTab = 2
                    } else {
                        selectedTab = 0
                    }
                    // ✅ Save originals for edit comparison
                    originalDate = selectedDate
                    originalRepeatDays = repeatDays
                    originalRepeatType = repeatType
                    originalHour = selectedHour
                    originalMinute = selectedMinute
                    originalAMPM = selectedAMPM
                }
            }
        }
    }
    
    // MARK: - One Time Tab
    struct OneTimeTabView: View {
        @Binding var selectedDate: Date?
        var showSummary: Bool = true
        var timeStr: String = ""
        
        @State private var currentMonth: Date = Date()
        @State private var showMonthYearPicker: Bool = false
        @State private var pickerYear: Int = Calendar.current.component(.year, from: Date())
        @State private var pickerMonth: Int = Calendar.current.component(.month, from: Date())
        
        private let monthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        private let calendar = Calendar.current
        
        private var daysInMonth: [Date?] {
            let range = calendar.range(of: .day, in: .month, for: currentMonth)!
            let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
            let firstWeekday = (calendar.component(.weekday, from: firstDay) + 5) % 7
            var days: [Date?] = Array(repeating: nil, count: firstWeekday)
            for day in range {
                var comps = calendar.dateComponents([.year, .month], from: currentMonth)
                comps.day = day
                days.append(calendar.date(from: comps))
            }
            return days
        }
        
        private var monthYearTitle: String {
            let f = DateFormatter()
            f.dateFormat = "MMMM yyyy"
            return f.string(from: currentMonth)
        }
        
        var body: some View {
            VStack(spacing: 16) {
                // ✅ Summary outside card above calendar
                if showSummary, let date = selectedDate {
                    let day = Calendar.current.component(.day, from: date)
                    let monthYear = {
                        let f = DateFormatter()
                        f.dateFormat = "MMMM yyyy"
                        return f.string(from: currentMonth)
                    }()
                    VStack(spacing: 2) {
                        HStack(spacing: 8) {
                            if !timeStr.isEmpty {
                                Text(timeStr)
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(.orange)
                                Text("·")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(.orange.opacity(0.5))
                            }
                            Text("Day \(day)")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.3), value: day)
                        }
                        Text(monthYear)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                    .padding(.vertical, 8)
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color("CardBackground"))
                    VStack(spacing: 12) {
                        HStack {
                        }
                        HStack {
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                                    .foregroundStyle(.orange)
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            Spacer()
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    showMonthYearPicker.toggle()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(monthYearTitle)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(.orange)
                                    Image(systemName: showMonthYearPicker ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                                }
                            } label: {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.orange)
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .padding(.horizontal, 4)
                        
                        if showMonthYearPicker {
                            VStack(spacing: 10) {
                                let currentYear = calendar.component(.year, from: Date())
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(currentYear...(currentYear + 10), id: \.self) { year in
                                            Button {
                                                pickerYear = year
                                                var comps = calendar.dateComponents([.month], from: currentMonth)
                                                comps.year = year
                                                if let newDate = calendar.date(from: comps) {
                                                    currentMonth = newDate
                                                }
                                            } label: {
                                                Text(String(format: "%d", year))
                                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                                    .foregroundStyle(pickerYear == year ? .black : Color("SecondaryText"))
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 6)
                                                    .background(pickerYear == year ? Color.orange : Color("AppBackground"))
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                }
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                                    ForEach(0..<12, id: \.self) { i in
                                        Button {
                                            pickerMonth = i + 1
                                            var comps = DateComponents()
                                            comps.year = pickerYear
                                            comps.month = i + 1
                                            if let newDate = calendar.date(from: comps) {
                                                currentMonth = newDate
                                            }
                                        } label: {
                                            Text(monthNames[i])
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                                .foregroundStyle(pickerMonth == (i + 1) ? .black : Color("SecondaryText"))
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 8)
                                                .background(pickerMonth == (i + 1) ? Color.orange : Color("AppBackground"))
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                    }
                                }
                            }
                            .transition(.opacity)
                        }
                        
                        HStack(spacing: 0) {
                            ForEach(["M","T","W","TH","F","SA","S"], id: \.self) { d in
                                Text(d)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color("SecondaryText"))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                            ForEach(0..<daysInMonth.count, id: \.self) { index in
                                if let date = daysInMonth[index] {
                                    let isPast = date < calendar.startOfDay(for: Date())
                                    let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                                    let isToday = calendar.isDateInToday(date)
                                    Button {
                                        if !isPast {
                                            withAnimation(.spring(response: 0.3)) {
                                                selectedDate = date
                                            }
                                        }
                                    } label: {
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    isSelected ? Color.orange :
                                                        isToday ? Color.orange.opacity(0.2) :
                                                        Color("AppBackground")
                                                )
                                                .frame(width: 36, height: 36)
                                            Text("\(calendar.component(.day, from: date))")
                                                .font(.system(size: 13, weight: isToday ? .bold : .semibold, design: .rounded))
                                                .foregroundStyle(
                                                    isPast ? Color.gray.opacity(0.3) :
                                                        isSelected ? .black : Color("PrimaryText")
                                                )
                                        }
                                    }
                                    .disabled(isPast)
                                } else {
                                    Color.clear.frame(width: 36, height: 36)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 4)
            Text("⏰ Rings once on the selected date at the set time.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Color("SecondaryText"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .onAppear {
                    if let existing = selectedDate {
                        currentMonth = existing
                    }
                    pickerYear = calendar.component(.year, from: currentMonth)
                    pickerMonth = calendar.component(.month, from: currentMonth)
                }
                .onChange(of: currentMonth) { _, newValue in
                    pickerYear = calendar.component(.year, from: newValue)
                    pickerMonth = calendar.component(.month, from: newValue)
                }
        }
    }
    
    // MARK: - Monthly Tab
    struct MonthlyTabView: View {
        @Binding var repeatDays: Set<Int>
        @Binding var repeatType: String
        @Binding var selectedDay: Int
        @Binding var selectedMonths: Set<Int>
        @Binding var repeatMode: String
        @Binding var stopAfterYears: Int
        var timeStr: String = ""
        
        private let monthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        private let currentMonth = Calendar.current.component(.month, from: Date())
        
        private var maxDays: Int {
            let months = selectedMonths.filter { $0 >= 101 && $0 <= 112 }.map { $0 - 100 }
            if months.isEmpty { return 31 }
            return months.map { month -> Int in
                switch month {
                case 2: return 29
                case 4, 6, 9, 11: return 30
                default: return 31
                }
            }.min() ?? 31
        }
        
        var body: some View {
            VStack(spacing: 16) {
                
                // Summary
                VStack(spacing: 4) {
                    if selectedDay > 0 {
                        let monthStr = (selectedMonths.isEmpty || selectedMonths.count == 12) ? "Every month" :
                        selectedMonths.sorted().map { monthNames[$0 - 101] }.joined(separator: ", ")
                        
                        let currentYear = Calendar.current.component(.year, from: Date())
                        let repeatStr: String = {
                            switch repeatMode {
                            case "once": return "\(monthStr) · This year only"
                            case "forever": return "\(monthStr) · Forever"
                            case "stopafter": return "\(monthStr) · Until \(currentYear + stopAfterYears)"
                            default: return monthStr
                            }
                        }()
                        HStack(spacing: 8) {
                            if !timeStr.isEmpty {
                                Text(timeStr)
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(.orange)
                                Text("·")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(.orange.opacity(0.5))
                            }
                            Text("Day \(selectedDay)")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.3), value: selectedDay)
                        }
                        Text(repeatStr)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.orange.opacity(0.8))
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Select a day")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color("SecondaryText"))
                    }
                }
                .padding(.vertical, 8)
                
                // Day grid
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color("CardBackground"))
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pick day of month")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color("PrimaryText"))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                            ForEach(1...31, id: \.self) { day in
                                let isSelected = selectedDay == day
                                let isAvailable = day <= maxDays
                                Button {
                                    if isAvailable {
                                        withAnimation(.spring(response: 0.3)) {
                                            selectedDay = selectedDay == day ? 0 : day
                                        }
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(isSelected ? Color.orange : Color("AppBackground"))
                                            .frame(width: 36, height: 36)
                                        Text("\(day)")
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundStyle(
                                                !isAvailable ? Color.gray.opacity(0.3) :
                                                    isSelected ? .black : Color("PrimaryText")
                                            )
                                    }
                                }
                                .disabled(!isAvailable)
                                .opacity(isAvailable ? 1.0 : 0.0)
                                .scaleEffect(isAvailable ? 1.0 : 0.1)
                                .animation(.spring(response: 0.4, dampingFraction: 0.55), value: maxDays)
                            }
                        }
                    }
                    .padding(16)
                }
                .padding(.horizontal, 20)
                
                // Month selector
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color("CardBackground"))
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Which months?")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color("PrimaryText"))
                            Spacer()
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    if selectedMonths.count == 12 {
                                        selectedMonths = []
                                    } else {
                                        selectedMonths = Set(101...112)
                                    }
                                }
                            } label: {
                                Text(selectedMonths.count == 12 ? "Clear all" : "Select all")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.orange)
                            }
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                            ForEach(0..<12, id: \.self) { i in
                                let monthValue = 101 + i
                                let isSelected = selectedMonths.contains(monthValue)
                                let isPast = (i + 1) < currentMonth
                                Button {
                                    if !isPast {
                                        withAnimation(.spring(response: 0.3)) {
                                            if isSelected {
                                                selectedMonths.remove(monthValue)
                                            } else {
                                                selectedMonths.insert(monthValue)
                                            }
                                        }
                                    }
                                } label: {
                                    Text(monthNames[i])
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(
                                            isPast ? Color("SecondaryText").opacity(0.25) :
                                                isSelected ? .black : Color("SecondaryText")
                                        )
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            isPast ? Color.clear :
                                                isSelected ? Color.orange : Color("AppBackground")
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .disabled(isPast)
                            }
                        }
                    }
                    .padding(16)
                }
                .padding(.horizontal, 20)
                
                // Repeat until
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color("CardBackground"))
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Repeat until?")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color("PrimaryText"))
                        }
                        HStack(spacing: 8) {
                            Button {
                                withAnimation(.spring(response: 0.3)) { repeatMode = "once" }
                            } label: {
                                Text("Once")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(repeatMode == "once" ? .black : Color("SecondaryText"))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(repeatMode == "once" ? Color.orange : Color("AppBackground"))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Button {
                                withAnimation(.spring(response: 0.3)) { repeatMode = "forever" }
                            } label: {
                                Text("Forever")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(repeatMode == "forever" ? .black : Color("SecondaryText"))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(repeatMode == "forever" ? Color.orange : Color("AppBackground"))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Button {
                                withAnimation(.spring(response: 0.3)) { repeatMode = "stopafter" }
                            } label: {
                                Text("Stop after")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(repeatMode == "stopafter" ? .black : Color("SecondaryText"))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(repeatMode == "stopafter" ? Color.orange : Color("AppBackground"))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        if repeatMode == "stopafter" {
                            HStack {
                                Text("Stop after \(stopAfterYears) year\(stopAfterYears > 1 ? "s" : "")")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color("PrimaryText"))
                                Spacer()
                                Stepper("", value: $stopAfterYears, in: 1...20)
                                    .labelsHidden()
                            }
                            .padding(10)
                            .background(Color("AppBackground"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            let currentYear = Calendar.current.component(.year, from: Date())
                            Text("Stops after \(currentYear + stopAfterYears)")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(16)
                }
                .padding(.horizontal, 20)
                VStack(alignment: .leading, spacing: 4) {
                    Text("🔁 Rings on the selected day every month or specific months.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color("SecondaryText"))
                    Text("Once = this year only · Forever = never stops · Stop after = stops after X years")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color("SecondaryText"))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
    
    // MARK: - Yearly Tab
    struct YearlyTabView: View {
        @Binding var repeatDays: Set<Int>
        @Binding var repeatType: String
        @Binding var selectedDate: Date?
        @Binding var repeatOn: Bool
        @Binding var repeatCount: Int
        var timeStr: String = ""
        
        private let calendar = Calendar.current
        private let currentYear = Calendar.current.component(.year, from: Date())
        private let currentMonth = Calendar.current.component(.month, from: Date())
        
        private var startYear: Int {
            guard let date = selectedDate else { return currentYear }
            let month = calendar.component(.month, from: date)
            return month > currentMonth ? currentYear : currentYear + 1
        }
        
        private var yearRange: String {
            return "\(startYear) → \(startYear + repeatCount - 1)"
        }
        
        var body: some View {
            VStack(spacing: 16) {
                
                VStack(spacing: 4) {
                    if let date = selectedDate {
                        let day = calendar.component(.day, from: date)
                        let monthYear = {
                            let f = DateFormatter()
                            f.dateFormat = "MMMM"
                            return f.string(from: date)
                        }()
                        HStack(spacing: 8) {
                            if !timeStr.isEmpty {
                                Text(timeStr)
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(.orange)
                                Text("·")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundStyle(.orange.opacity(0.5))
                            }
                            Text("Day \(day)")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.3), value: day)
                        }
                        HStack(spacing: 6) {
                            Text(monthYear)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.orange.opacity(0.8))
                            if repeatOn {
                                Text("· \(yearRange)")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.orange.opacity(0.8))
                            } else if let date = selectedDate {
                                let year = Calendar.current.component(.year, from: date)
                                Text("· \(String(format: "%d", year))")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.orange.opacity(0.8))
                            }
                        }
                        
                    } else {
                        Text("Select a date")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color("SecondaryText"))
                    }
                }
                .padding(.vertical, 8)
                
                OneTimeTabView(selectedDate: $selectedDate, showSummary: false, timeStr: timeStr)
                
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color("CardBackground"))
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Repeat yearly?")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color("PrimaryText"))
                            Spacer()
                            Toggle("", isOn: $repeatOn.animation(.spring(response: 0.3)))
                                .tint(.orange)
                                .labelsHidden()
                            Text(repeatOn ? "On" : "Off")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(repeatOn ? .orange : Color("SecondaryText"))
                        }
                        if repeatOn {
                            HStack {
                                Text("Repeat for \(repeatCount) years")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color("PrimaryText"))
                                Spacer()
                                Stepper("", value: $repeatCount, in: 1...20)
                                    .labelsHidden()
                            }
                            .padding(10)
                            .background(Color("AppBackground"))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            Text("\(yearRange)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(16)
                }
                .padding(.horizontal, 20)
                Text("📅 Rings once or every year on the selected date.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color("SecondaryText"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
    }
}
