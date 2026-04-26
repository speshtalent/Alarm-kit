import SwiftUI
import AVFoundation
import EventKit

struct AddAlarmView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("use24HourFormat") private var use24HourFormat: Bool = false

    @State private var selectedHour: Int
    @State private var selectedMinute: Int
    @State private var selectedDate: Date
    @State private var useSpecificDate: Bool
    @State private var title: String
    @State private var snoozeEnabled = true
    @State private var snoozeDuration = 5
    @State private var selectedSound = "nokia.caf"
    @State private var addToCalendar = false
    @State private var selectedAMPM: Int

    @State private var isRecording = false
    @State private var hasRecording = false
    @State private var isJustRecorded = false
    @State private var recordingName = ""
    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioPlayer: AVAudioPlayer?

    @State private var playingSound: String? = nil
    @State private var soundPlayer: AVAudioPlayer? = nil

    @State private var repeatDays: Set<Int> = []
    @State private var showPastDateAlert = false
    @State private var didAutoStartRecording = false
    @State private var showScheduleSheet = false
    @State private var scheduledDate: Date? = nil
    @State private var showHourPicker = false
    @State private var showMinutePicker = false
    
    @State private var customRecordings: [(name: String, file: String)] = []
    @State private var saveToList: Bool = false
    @State private var showMyRecordings: Bool = false
    @State private var editingRecordingFile: String? = nil
    @State private var editingRecordingName: String = ""
    @State private var selectedDayOfMonth: Int = 1
    @State private var selectedYears: Set<Int> = []
    @State private var originalHour: Int = 0
    @State private var originalMinute: Int = 0
    @State private var originalAMPM: Int = 0
    @State private var originalTitle: String = ""
    @State private var originalSound: String = "nokia.caf"
    @State private var originalRepeatDays: Set<Int> = []
    @State private var originalRepeatType: String = ""
    @State private var originalDayOfMonth: Int = 1
    @State private var originalSnoozeEnabled: Bool = true
    @State private var originalSnoozeDuration: Int = 5
    @State private var originalAddToCalendar: Bool = false
    @State private var originalScheduledDate: Date? = nil

    // ✅ "" = no repeat, "weekly", "monthly", "yearly"
    @State private var repeatType: String = ""

    private var editingAlarmID: String?
    var hideDateToggle: Bool = false
    private let autoStartRecording: Bool

    let sounds: [(name: String, file: String)] = [
        (name: "Nokia", file: "nokia.caf"),
        (name: "1985 Ring", file: "1985_ring2.caf"),
        (name: "Sony", file: "sony.caf"),
        (name: "Bells", file: "bells.caf"),
        (name: "Bird Sound", file: "bird-sound.caf"),
        (name: "Childhood", file: "childhood.caf"),
        (name: "Morning Birds", file: "morning-birds.caf"),
        (name: "Pure", file: "pure.caf"),
        (name: "Rings", file: "rings.caf"),
        (name: "Soft", file: "soft.caf")
    ]

    let weekDays: [(label: String, value: Int)] = [
        ("Mon", 2), ("Tue", 3), ("Wed", 4),
        ("Thu", 5), ("Fri", 6), ("Sat", 7), ("Sun", 1)
    ]

    var onSave: (Date, String, Bool, TimeInterval, String, Set<Int>, Bool) -> Void

    init(
        preselectedDate: Date? = nil,
        initialTitle: String? = nil,
        editingItem: AlarmService.AlarmListItem? = nil,
        hideDateToggle: Bool = false,
        autoStartRecording: Bool = false,
        repeatDaysToLoad: Set<Int> = [],
        soundToLoad: String = "nokia.caf",
        onSave: @escaping (Date, String, Bool, TimeInterval, String, Set<Int>, Bool) -> Void
    ) {
        self.hideDateToggle = hideDateToggle
        self.autoStartRecording = autoStartRecording
        self.onSave = onSave
        _repeatDays = State(initialValue: repeatDaysToLoad)
        // ✅ Load selectedDayOfMonth from repeatDaysToLoad
        // ✅ Load selectedDayOfMonth (1-31)
        let dayValue = repeatDaysToLoad.filter { $0 >= 1 && $0 <= 31 }.first ?? 1
        _selectedDayOfMonth = State(initialValue: dayValue)

        // ✅ Load selectedYears (2025+)
        let yearsFromLoad = repeatDaysToLoad.filter { $0 >= 2025 }
        _selectedYears = State(initialValue: yearsFromLoad)

        // ✅ Fix repeatDays to only contain months (101-112) not day/year values
        let monthsOnly = repeatDaysToLoad.filter { $0 >= 101 && $0 <= 112 }
        let hasYearsInLoad = repeatDaysToLoad.contains { $0 >= 2025 }
        let hasMonthsOrGeneric = !monthsOnly.isEmpty || repeatDaysToLoad.contains(100)
        if hasYearsInLoad {
            // ✅ Yearly — keep everything
            _repeatDays = State(initialValue: repeatDaysToLoad)
        } else {
            _repeatDays = State(initialValue: hasMonthsOrGeneric ? repeatDaysToLoad : (monthsOnly.isEmpty && !repeatDaysToLoad.isEmpty ? repeatDaysToLoad : monthsOnly))
        }



        let hasMonths = repeatDaysToLoad.contains { $0 >= 101 && $0 <= 112 }
        let hasWeekDays = repeatDaysToLoad.contains { $0 >= 1 && $0 <= 7 } &&
                          !repeatDaysToLoad.contains { $0 >= 8 && $0 <= 31 } &&
                          !repeatDaysToLoad.contains { $0 >= 100 }
        let hasYears = repeatDaysToLoad.contains { $0 >= 2025 }
        let isMonthlyGeneric = repeatDaysToLoad == Set([100])
        let isDayInMonth = repeatDaysToLoad.contains { $0 >= 1 && $0 <= 31 } && !hasWeekDays

        if hasYears {
            _repeatType = State(initialValue: "yearly")
        } else if isMonthlyGeneric || hasMonths || isDayInMonth {
            _repeatType = State(initialValue: "monthly")
        } else if hasWeekDays {
            _repeatType = State(initialValue: "weekly")
        } else {
            _repeatType = State(initialValue: "")
        }

        if let item = editingItem, let fireDate = item.fireDate {
            _title = State(initialValue: item.label)
            let adjustedDate = fireDate <= Date() ? (Calendar.current.date(byAdding: .day, value: 1, to: fireDate) ?? fireDate) : fireDate
            _selectedDate = State(initialValue: adjustedDate)
            let hour24 = Calendar.current.component(.hour, from: fireDate)
            let is24Hr = UserDefaults.standard.bool(forKey: "use24HourFormat")
            let hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24)
            _selectedHour = State(initialValue: is24Hr ? hour24 : hour12)
            _selectedAMPM = State(initialValue: hour24 < 12 ? 0 : 1)
            _selectedMinute = State(initialValue: Calendar.current.component(.minute, from: fireDate))
            _useSpecificDate = State(initialValue: true)
            self.editingAlarmID = item.id.uuidString
            if soundToLoad != "nokia.caf" {
                _selectedSound = State(initialValue: soundToLoad)
            }
        } else if let date = preselectedDate, !Calendar.current.isDateInToday(date) {
            _title = State(initialValue: "")
            _selectedDate = State(initialValue: date)
            let now = Date()
            let hour24 = Calendar.current.component(.hour, from: now)
            let is24Hr = UserDefaults.standard.bool(forKey: "use24HourFormat")
            let hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24)
            _selectedHour = State(initialValue: is24Hr ? hour24 : hour12)
            _selectedAMPM = State(initialValue: hour24 < 12 ? 0 : 1)
            _selectedMinute = State(initialValue: Calendar.current.component(.minute, from: now))
            _useSpecificDate = State(initialValue: true)
            self.editingAlarmID = nil
            let day = Calendar.current.component(.day, from: date)
            let month = Calendar.current.component(.month, from: date)
            let year = Calendar.current.component(.year, from: date)
            let currentYear = Calendar.current.component(.year, from: Date())
            _selectedDayOfMonth = State(initialValue: day)
            if year > currentYear {
                // ✅ Future year → use yearly with that specific year
                var yearlyDays: Set<Int> = []
                yearlyDays.insert(day)
                yearlyDays.insert(100 + month)
                yearlyDays.insert(year)
                _repeatDays = State(initialValue: yearlyDays)
                _repeatType = State(initialValue: "yearly")
            } else {
                // ✅ Same year → one time with scheduledDate
                _repeatDays = State(initialValue: [])
                _repeatType = State(initialValue: "")
            }
        } else {
            _title = State(initialValue: "")  // ✅ must be first
            _selectedDate = State(initialValue: Date())
            let hour24 = Calendar.current.component(.hour, from: Date())
            let is24Hr = UserDefaults.standard.bool(forKey: "use24HourFormat")
            let hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24)
            _selectedHour = State(initialValue: is24Hr ? hour24 : hour12)
            _selectedAMPM = State(initialValue: hour24 < 12 ? 0 : 1)
            _selectedMinute = State(initialValue: Calendar.current.component(.minute, from: Date()))
            _useSpecificDate = State(initialValue: false)
            self.editingAlarmID = nil
        }
    }

    private var tempRecordingURL: URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let soundsURL = libraryURL.appendingPathComponent("Sounds")
        try? FileManager.default.createDirectory(at: soundsURL, withIntermediateDirectories: true)
        return soundsURL.appendingPathComponent("alarm_voice_temp.caf")
    }

    private func voiceURL(for alarmID: String) -> URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let soundsURL = libraryURL.appendingPathComponent("Sounds")
        return soundsURL.appendingPathComponent("alarm_voice_\(alarmID).caf")
    }

    private var legacyVoiceURL: URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return libraryURL.appendingPathComponent("Sounds/alarm_voice.caf")
    }

    private func voiceNameKey(for alarmID: String) -> String {
        return "voiceRecordingName_\(alarmID)"
    }

    private var fireDate: Date {
        let hour24: Int
        if use24HourFormat {
            hour24 = selectedHour
        } else {
            var h = selectedHour % 12
            if selectedAMPM == 1 { h += 12 }
            hour24 = h
        }
        // ✅ If scheduledDate is set, use it as base (one-time or yearly)
        if let scheduled = scheduledDate, repeatType == "" {
            var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: scheduled)
            components.hour = hour24
            components.minute = selectedMinute
            components.second = 0
            var date = Calendar.current.date(from: components) ?? Date()
            // ✅ If yearly and date is in past, find next future year
            if repeatType == "yearly" && date < Date() {
                components.year = (components.year ?? Calendar.current.component(.year, from: Date())) + 1
                date = Calendar.current.date(from: components) ?? date
            }
            return date
        }
        let baseDate: Date
        if repeatType == "monthly" {
            let day = repeatDays.filter { $0 >= 1 && $0 <= 31 }.first ?? selectedDayOfMonth
            let selectedMonths = repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted()
            let cal = Calendar.current
            if selectedMonths.isEmpty {
                // ✅ Every month — find next future occurrence and return early
                let now = Date()
                let currentDay = cal.component(.day, from: now)
                let currentMonth = cal.component(.month, from: now)
                let currentYear = cal.component(.year, from: now)
                var comps = DateComponents()
                comps.day = day
                comps.hour = hour24
                comps.minute = selectedMinute
                comps.second = 0
                if day > currentDay {
                    comps.month = currentMonth
                    comps.year = currentYear
                } else if day == currentDay {
                    // ✅ Today — use today if time is still in future
                    comps.month = currentMonth
                    comps.year = currentYear
                    let todayDate = cal.date(from: comps)
                    if let td = todayDate, td > Date() {
                        return td
                    }
                    // ✅ Time already passed today — go next month
                    if currentMonth == 12 {
                        comps.month = 1
                        comps.year = currentYear + 1
                    } else {
                        comps.month = currentMonth + 1
                        comps.year = currentYear
                    }
                } else {
                    if currentMonth == 12 {
                        comps.month = 1
                        comps.year = currentYear + 1
                    } else {
                        comps.month = currentMonth + 1
                        comps.year = currentYear
                    }
                }
                return cal.date(from: comps) ?? Date()
            } else {
                // ✅ Specific months selected
                let month = selectedMonths.min().map { $0 - 100 } ?? cal.component(.month, from: Date())
                let year = selectedYears.min() ?? cal.component(.year, from: Date())
                var comps = DateComponents()
                comps.year = year
                comps.month = month
                comps.day = day
                baseDate = cal.date(from: comps) ?? selectedDate
            }
        } else {
            if repeatType == "yearly" {
                // ✅ Yearly — return early to avoid past date override
                let years = repeatDays.filter { $0 >= 2025 }.sorted()
                let months = repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted()
                let day = repeatDays.filter { $0 >= 1 && $0 <= 31 }.first ?? Calendar.current.component(.day, from: Date())
                let month = months.first.map { $0 - 100 } ?? Calendar.current.component(.month, from: Date())
                let year = years.first ?? Calendar.current.component(.year, from: Date())
                var comps = DateComponents()
                comps.year = year
                comps.month = month
                comps.day = day
                comps.hour = hour24
                comps.minute = selectedMinute
                comps.second = 0
                return Calendar.current.date(from: comps) ?? Date()
            } else if editingAlarmID != nil && Calendar.current.isDateInToday(selectedDate) {
                baseDate = Date()
            } else {
                baseDate = !Calendar.current.isDateInToday(selectedDate) ? selectedDate : Date()
            }
        }
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: baseDate)
        components.hour = hour24
        components.minute = selectedMinute
        components.second = 0
        var date = Calendar.current.date(from: components) ?? Date()
        if date < Date().addingTimeInterval(-60) {
            date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        } else if editingAlarmID != nil && date < Date().addingTimeInterval(30) {
            date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return date
    }
    private var ringsAtText: String {
        let date = fireDate
        let formatter = DateFormatter()
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        // WHY: The confirmation copy should match the same 12/24-hour preference
        // the rest of the alarm editor uses, otherwise the preview disagrees with the picker.
        formatter.dateFormat = use24HourFormat ? "HH:mm" : "h:mm a"
        let timeStr = formatter.string(from: date)
        let calendar = Calendar.current

        // ✅ Weekly
        if repeatType == "weekly" && !repeatDays.isEmpty {
            let dayStr: String
            if repeatDays.count == 7 {
                dayStr = "every day"
            } else if repeatDays == Set([2,3,4,5,6]) {
                dayStr = "weekdays"
            } else if repeatDays == Set([7,1]) {
                dayStr = "weekends"
            } else {
                let ordered = weekDays.filter { repeatDays.contains($0.value) }.map { $0.label }
                dayStr = ordered.joined(separator: ", ")
            }
            return "Rings every \(dayStr) at \(timeStr)"
        }

        // ✅ Monthly with selected months
        if repeatType == "monthly" {
            let day = repeatDays.filter { $0 >= 1 && $0 <= 31 }.first ?? selectedDayOfMonth
            let months = repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted()
            let isForever = repeatDays.contains(100)
            let stopYear = repeatDays.filter { $0 >= 201 }.first.map { $0 - 200 }
            let monthNamesLocal = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
            let monthStr = (months.isEmpty || months.count == 12) ? "every month" : months.map { monthNamesLocal[$0 - 101] }.joined(separator: ", ")
            let repeatStr: String = {
                if isForever { return "· Forever" }
                if let stop = stopYear { return "· Until \(Calendar.current.component(.year, from: Date()) + stop)" }
                return "· This year only"
            }()
            return "Rings on day \(day) of \(monthStr) \(repeatStr) at \(timeStr)"
        }

        // ✅ Yearly
        if repeatType == "yearly" {
            let monthNamesLocal = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
            let day = repeatDays.filter { $0 >= 1 && $0 <= 31 }.first ?? 0
            let months = repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted()
            let monthStr = months.isEmpty ? "" : monthNamesLocal[months[0] - 101]
            let years = repeatDays.filter { $0 >= 2025 }.sorted()
            if years.count > 1 {
                return "Rings on \(monthStr) \(day) · \(years.first!) → \(years.last!) at \(timeStr)"
            } else if years.count == 1 {
                return "Rings on \(monthStr) \(day) · \(years[0]) at \(timeStr)"
            }
            return "Rings on \(monthStr) \(day) every year at \(timeStr)"
        }


        // ✅ One time
        if calendar.isDateInToday(date) {
            return "Rings at \(timeStr) · Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Rings at \(timeStr) · Tomorrow"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d, yyyy"
            return "Rings at \(timeStr) · \(dateFormatter.string(from: date))"
        }
    }

    private var isEditing: Bool { editingAlarmID != nil }
    private var hasChanges: Bool {
        guard isEditing else { return true }
        return selectedHour != originalHour ||
               selectedMinute != originalMinute ||
               selectedAMPM != originalAMPM ||
               title != originalTitle ||
               selectedSound != originalSound ||
               finalRepeatDays != originalRepeatDays ||
               repeatType != originalRepeatType ||
               selectedDayOfMonth != originalDayOfMonth ||
               snoozeEnabled != originalSnoozeEnabled ||
               snoozeDuration != originalSnoozeDuration ||
               addToCalendar != originalAddToCalendar ||
               scheduledDate != originalScheduledDate
    }

    private var isSpecificDateInPast: Bool {
        guard useSpecificDate else { return false }
        return fireDate <= Date() && repeatDays.isEmpty && repeatType == ""
    }

    private var finalRepeatDays: Set<Int> {
        switch repeatType {
        case "monthly": return repeatDays
        case "yearly": return repeatDays
        case "weekly": return repeatDays
        default: return []
        }
    }

    var body: some View {
        ZStack {
            Color("AppBackground").ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Text(isEditing ? "Edit Alarm" : "New Alarm")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("PrimaryText"))



                    // Picker card — Calendar style
                    ZStack {
                        RoundedRectangle(cornerRadius: 20).fill(Color("CardBackground"))
                        VStack(spacing: 0) {
                            // Orange rings header
                            Text(ringsAtText)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.black)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(Color.orange)
                                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 20))


                            // Big time display
                            HStack(spacing: 0) {
                                Spacer()
                                VStack(spacing: 2) {
                                    Text("HR")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color("SecondaryText"))
                                        .tracking(2)
                                    Text(use24HourFormat ? String(format: "%02d", selectedHour) : String(format: "%d", selectedHour))
                                        .font(.system(size: 72, weight: .heavy, design: .rounded))
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
                                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 4)
                                    .padding(.bottom, 20)
                                VStack(spacing: 2) {
                                    Text("MIN")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color("SecondaryText"))
                                        .tracking(2)
                                    Text(String(format: "%02d", selectedMinute))
                                        .font(.system(size: 72, weight: .heavy, design: .rounded))
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
                                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                                .foregroundStyle(selectedAMPM == 0 ? .black : Color("SecondaryText"))
                                                .frame(width: 54, height: 38)
                                                .background(selectedAMPM == 0 ? Color.orange : Color("AppBackground"))
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                        Button {
                                            withAnimation(.spring(response: 0.3)) { selectedAMPM = 1 }
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        } label: {
                                            Text("PM")
                                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                                .foregroundStyle(selectedAMPM == 1 ? .black : Color("SecondaryText"))
                                                .frame(width: 54, height: 38)
                                                .background(selectedAMPM == 1 ? Color.orange : Color("AppBackground"))
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                    }
                                    .padding(.leading, 8)
                                    .padding(.bottom, 4)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 16)

                            // Hour wheel picker
                            if showHourPicker {
                                VStack(spacing: 8) {
                                    Text("SET HOUR")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color("SecondaryText"))
                                        .tracking(2)
                                    Picker("Hour", selection: $selectedHour) {
                                        if use24HourFormat {
                                            ForEach(0...23, id: \.self) { h in
                                                Text(String(format: "%02d", h))
                                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                                    .tag(h)
                                            }
                                        } else {
                                            ForEach(1...12, id: \.self) { h in
                                                Text(String(format: "%d", h))
                                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                                    .tag(h)
                                            }
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    .frame(height: 120)
                                    .background(Color("AppBackground"))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            // Minute wheel picker
                            if showMinutePicker {
                                VStack(spacing: 8) {
                                    Text("SET MINUTE")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color("SecondaryText"))
                                        .tracking(2)
                                    Picker("Minute", selection: $selectedMinute) {
                                        ForEach(0...59, id: \.self) { m in
                                            Text(String(format: "%02d", m))
                                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                                .tag(m)
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    .frame(height: 120)
                                    .background(Color("AppBackground"))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    // Single Repeat card
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(Color("CardBackground"))
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "repeat").foregroundStyle(.orange)
                                Text("Repeat")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color("PrimaryText"))
                                Spacer()
                                if repeatType == "weekly" && !repeatDays.isEmpty {
                                    let label = repeatDays.count == 7 ? "Every day" :
                                        repeatDays == Set([2,3,4,5,6]) ? "Weekdays" :
                                        repeatDays == Set([7,1]) ? "Weekends" :
                                        weekDays.filter { repeatDays.contains($0.value) }.map { $0.label }.joined(separator: ", ")
                                    Text(label)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(.orange)
                                } else if repeatType == "monthly" {
                                    Text("Monthly")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(.orange)
                                }
                            }
                            Divider()
                            HStack(spacing: 6) {
                                ForEach(weekDays, id: \.value) { day in
                                    let isSelected = repeatType == "weekly" && repeatDays.contains(day.value)
                                    Button {
                                        if isSelected {
                                            repeatDays.remove(day.value)
                                        } else {
                                            repeatDays.insert(day.value)
                                        }
                                        repeatType = repeatDays.isEmpty ? (repeatType == "monthly" ? "monthly" : "") : "weekly"
                                        // ✅ Clear scheduled date when weekly selected
                                        if !repeatDays.isEmpty {
                                            scheduledDate = nil
                                        }
                                    }label: {
                                        Text(day.label)
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundStyle(isSelected ? .black : Color("SecondaryText"))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(isSelected ? Color.orange : Color("AppBackground"))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .opacity(repeatType == "monthly" ? 0.3 : 1.0)
                                    .disabled(repeatType == "monthly")
                                }
                            }

                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 20)
                    
                    // ✅ Schedule for Future button
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color("CardBackground"))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke((scheduledDate != nil || (repeatType == "monthly" && !repeatDays.isEmpty) || (repeatType == "yearly" && !repeatDays.isEmpty)) ? Color.orange.opacity(0.6) : Color.orange.opacity(0.2), lineWidth: 1)

                            )
                        Button {
                            showScheduleSheet = true
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    let isScheduled = scheduledDate != nil || (repeatType == "monthly" && !repeatDays.isEmpty) || (repeatType == "yearly" && !repeatDays.isEmpty)
                                    Circle()
                                        .fill(isScheduled ? Color.orange : Color.orange.opacity(0.15))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: "calendar.badge.clock")
                                        .foregroundStyle(isScheduled ? .black : .orange)                                        .font(.system(size: 22))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Schedule for Future")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color("SecondaryText"))
                                    if let date = scheduledDate, repeatType != "yearly" {
                                        Text(formatScheduledDate(date))
                                            .font(.system(size: 18, weight: .bold, design: .rounded))
                                            .foregroundStyle(Color("PrimaryText"))
                                    } else if repeatType == "monthly" && !repeatDays.isEmpty {
                                        let monthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
                                        let day = repeatDays.filter { $0 >= 1 && $0 <= 31 }.first ?? 0
                                        let monthsArray = repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted()
                                        let months = monthsArray.map { monthNames[$0 - 101] }.joined(separator: ", ")
                                        let isForever = repeatDays.contains(100)
                                        let stopYear = repeatDays.filter { $0 >= 201 }.first.map { $0 - 200 }
                                        let repeatStr: String = {
                                            if isForever { return "Forever" }
                                            if let stop = stopYear { return "Until \(Calendar.current.component(.year, from: Date()) + stop)" }
                                            return "This year only"
                                        }()
                                        let monthStr = (monthsArray.isEmpty || monthsArray.count == 12) ? "Every month" : months
                                        Text("Day \(day) · \(monthStr) · \(repeatStr)")
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundStyle(Color("PrimaryText"))
                                            .multilineTextAlignment(.leading)
                                    } else if repeatType == "yearly" && !repeatDays.isEmpty {
                                        let monthNamesLocal = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
                                        let day = repeatDays.filter { $0 >= 1 && $0 <= 31 }.first ?? 0
                                        let months = repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted()
                                        let monthStr = months.isEmpty ? "" : monthNamesLocal[months[0] - 101]
                                        let years = repeatDays.filter { $0 >= 2025 }.sorted()
                                        let yearStr = years.isEmpty ? "" : years.count == 1 ? "\(years[0])" : "\(years.first!) → \(years.last!)"
                                        Text("\(monthStr) \(day) · \(yearStr)")
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                            .foregroundStyle(Color("PrimaryText"))                                    } else {
                                        Text("One time · Monthly · Yearly")
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundStyle(Color("PrimaryText"))
                                    }
                                }
                                Spacer()
                                if scheduledDate != nil || (repeatType == "monthly" && !repeatDays.isEmpty) || (repeatType == "yearly" && !repeatDays.isEmpty) {
                                    Button {
                                        withAnimation(.spring(response: 0.3)) {
                                            scheduledDate = nil
                                            repeatType = ""
                                            repeatDays = []
                                        }
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundStyle(Color("SecondaryText").opacity(0.6))
                                    }
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(16)
                        }
                        .opacity(repeatType == "weekly" ? 0.3 : 1.0)
                        .disabled(repeatType == "weekly")
                        // ✅ Clear weekly when schedule selected
                    }
                    .padding(.horizontal, 20)


                    // Title card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Alarm name/label")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color("SecondaryText"))
                            .padding(.horizontal, 4)

                        ZStack {
                            RoundedRectangle(cornerRadius: 16).fill(Color("CardBackground"))
                            HStack {
                                Image(systemName: "tag").foregroundStyle(.orange)
                                TextField("Give this alarm a name (optional)", text: $title)
                                    .foregroundStyle(Color("PrimaryText")).tint(.orange)
                            }
                            .padding(16)
                        }
                        .frame(height: 54)
                    }
                    .padding(.horizontal, 20)

                    // Voice card
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(Color("CardBackground"))
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "mic.fill").foregroundStyle(.orange)
                                Text("Custom Sound")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color("PrimaryText"))
                                Spacer()
                                if hasRecording {
                                    Text("Recorded ✓")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.green)
                                }
                            }
                            Divider()
                            Text("Record your voice — it will play when alarm fires")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Color("SecondaryText"))
                            HStack(spacing: 12) {
                                Button { isRecording ? stopRecording() : startRecording() } label: {
                                    HStack {
                                        Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                        Text(isRecording ? "Stop" : "Record")
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                                    .background(isRecording ? Color.red : Color.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                if isRecording {
                                    Text("Recording...")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color("SecondaryText"))
                                }
                            }
                            if isJustRecorded {
                                VStack(alignment: .leading, spacing: 10) {
                                    Divider()
                                    HStack {
                                        Image(systemName: "pencil").foregroundStyle(.orange)
                                        TextField("Name your recording...", text: $recordingName)
                                            .foregroundStyle(Color("PrimaryText")).tint(.orange)
                                    }
                                    .padding(10)
                                    .background(Color("AppBackground"))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    // ✅ Save to list toggle
                                    HStack {
                                        Image(systemName: "list.bullet").foregroundStyle(.orange)
                                        Text("Save to My Recordings")
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                            .foregroundStyle(Color("PrimaryText"))
                                        Spacer()
                                        Toggle("", isOn: $saveToList).tint(.orange)
                                    }
                                    .padding(10)
                                    .background(Color("AppBackground"))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                    HStack(spacing: 12) {
                                        Button { playRecording() } label: {
                                            HStack {
                                                Image(systemName: "play.circle.fill")
                                                Text("Preview").font(.system(size: 14, weight: .semibold, design: .rounded))
                                            }
                                            .foregroundStyle(Color("PrimaryText"))
                                            .padding(.horizontal, 16).padding(.vertical, 10)
                                            .background(Color("AppBackground"))
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
                                        Button { saveRecordingWithName() } label: {
                                            HStack {
                                                Image(systemName: "checkmark.circle.fill")
                                                Text("Save").font(.system(size: 14, weight: .semibold, design: .rounded))
                                            }
                                            .foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 10)
                                            .background(Color.green).clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
                                        Button { deleteRecording() } label: {
                                            Image(systemName: "trash.circle.fill").foregroundStyle(.red).font(.system(size: 34))
                                        }
                                    }
                                }
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            if hasRecording && !isJustRecorded {
                                HStack {
                                    Image(systemName: "waveform").foregroundStyle(.orange)
                                    Text(recordingName.isEmpty ? "Voice Recording" : recordingName)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color("PrimaryText"))
                                    Spacer()
                                    Button { playRecording() } label: {
                                        Image(systemName: "play.circle.fill")
                                            .foregroundStyle(.orange)
                                            .font(.system(size: 22))
                                    }
                                    Button {
                                        hasRecording = false; isJustRecorded = false; recordingName = ""
                                        UserDefaults.standard.removeObject(forKey: "voiceRecordingName_temp")
                                    } label: {
                                        Image(systemName: "trash.circle.fill")
                                            .foregroundStyle(.red)
                                            .font(.system(size: 34))
                                    }
                                }
                                .padding(10)
                                .background(Color("AppBackground"))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            // ✅ My Recordings list — always show
                            Divider()
                            Button {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showMyRecordings.toggle()
                                }
                            } label: {
                                    HStack {
                                        Text("MY RECORDINGS")
                                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                                            .foregroundStyle(Color("SecondaryText"))
                                            .tracking(1.2)
                                        Spacer()
                                        Image(systemName: showMyRecordings ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Color("SecondaryText"))
                                    }
                                }
                                if showMyRecordings {
                                    if customRecordings.isEmpty {
                                        Text("No recordings yet")
                                            .font(.system(size: 14, design: .rounded))
                                            .foregroundStyle(Color("SecondaryText"))
                                            .padding(.vertical, 8)
                                    } else {
                                    ForEach(customRecordings, id: \.file) { recording in
                                    HStack(spacing: 12) {
                                        Button {
                                            let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                                            let url = libraryURL.appendingPathComponent("Sounds/\(recording.file)")
                                            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                                            try? AVAudioSession.sharedInstance().setActive(true)
                                            audioPlayer = try? AVAudioPlayer(contentsOf: url)
                                            audioPlayer?.play()
                                        } label: {
                                            Image(systemName: "play.circle.fill")
                                                .foregroundStyle(.orange)
                                                .font(.system(size: 22))
                                        }
                                        Text(recording.name)
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundStyle(Color("PrimaryText"))
                                        Spacer()
                                        if selectedSound == recording.file {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.orange)
                                                .font(.system(size: 18))
                                        }
                                        Button {
                                            editingRecordingFile = recording.file
                                            editingRecordingName = recording.name
                                        } label: {
                                            Image(systemName: "pencil.circle.fill")
                                                .foregroundStyle(.orange)
                                                .font(.system(size: 22))
                                        }
                                        Button {
                                            deleteCustomRecording(file: recording.file)
                                        } label: {
                                            Image(systemName: "trash.circle.fill")
                                                .foregroundStyle(.red)
                                                .font(.system(size: 22))
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 8)
                                    .background(selectedSound == recording.file ? Color.orange.opacity(0.15) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.3)) {
                                            selectedSound = recording.file
                                            hasRecording = true
                                            isJustRecorded = false
                                            recordingName = recording.name
                                            UserDefaults.standard.set(recording.name, forKey: "voiceRecordingName_temp")
                                            UserDefaults.standard.set(recording.file, forKey: "voiceRecordingFile_temp")
                                        }
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                                    }
                                } // ✅ closes else
                            }
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 20)
                    .animation(.easeInOut(duration: 0.3), value: isJustRecorded)
                    .animation(.easeInOut(duration: 0.3), value: hasRecording)
                    // Sound card
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(Color("CardBackground"))
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "bell.fill").foregroundStyle(.orange)
                                Text("Sound")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color("PrimaryText"))
                            }
                            Divider()
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(sounds, id: \.file) { sound in
                                        HStack(spacing: 12) {
                                            Button {
                                                if playingSound == sound.file {
                                                    stopSoundPreview()
                                                } else {
                                                    playSoundPreview(sound.file)
                                                }
                                            } label: {
                                                Image(systemName: playingSound == sound.file ? "stop.circle.fill" : "play.circle.fill")
                                                    .foregroundStyle(playingSound == sound.file ? .red : .orange)
                                                    .font(.system(size: 24))
                                            }
                                            Text(sound.name)
                                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                                .foregroundStyle(Color("PrimaryText"))
                                            Spacer()
                                            if selectedSound == sound.file && !selectedSound.hasPrefix("custom_voice_") && !selectedSound.hasPrefix("alarm_voice_") {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.orange)
                                                    .font(.system(size: 18))
                                            }
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 8)
                                        .background(selectedSound == sound.file && !selectedSound.hasPrefix("custom_voice_") && !selectedSound.hasPrefix("alarm_voice_") ? Color.orange.opacity(0.15) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedSound = sound.file
                                            hasRecording = false
                                            recordingName = ""
                                            UserDefaults.standard.removeObject(forKey: "voiceRecordingName_temp")
                                            UserDefaults.standard.removeObject(forKey: "voiceRecordingFile_temp")
                                        }
                                        Divider()
                                    }
                                }
                            }
                            .frame(height: 200)
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 20)

                    // Calendar card
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(Color("CardBackground"))
                        HStack {
                            Image(systemName: "calendar.badge.plus").foregroundStyle(.orange)
                            Text("Add to Calendar")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color("PrimaryText"))
                            Spacer()
                            Toggle("", isOn: $addToCalendar)
                                .tint(.orange)
                                .onChange(of: addToCalendar) { _, newValue in
                                    if newValue {
                                        CalendarService.shared.refreshAuthorizationStatus()
                                        let status = CalendarService.shared.authorizationStatus
                                        if CalendarService.shared.shouldShowPermissionUI && status == .denied {
                                            addToCalendar = false
                                            NotificationCenter.default.post(name: NSNotification.Name("showCalendarPermission"), object: nil)
                                        } else if status == .notDetermined {
                                            Task {
                                                await CalendarService.shared.requestPermissionIfNeeded()
                                                CalendarService.shared.refreshAuthorizationStatus()
                                                let newStatus = CalendarService.shared.authorizationStatus
                                                await MainActor.run {
                                                    if !CalendarService.hasCalendarAccess(status: newStatus) {
                                                        addToCalendar = false
                                                        NotificationCenter.default.post(name: NSNotification.Name("showCalendarPermission"), object: nil)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 20)

                    Button {
                        if isSpecificDateInPast {
                            showPastDateAlert = true
                            return
                        }
                        saveAlarm()
                    } label: {
                        Text(isEditing ? "Update Alarm" : "Set Alarm")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(hasChanges ? .black : Color("SecondaryText"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(hasChanges ? Color.orange : Color("CardBackground"))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .disabled(isEditing && !hasChanges)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationDestination(isPresented: $showScheduleSheet) {
            ScheduleForFutureSheet(
                selectedDate: $scheduledDate,
                repeatType: $repeatType,
                repeatDays: $repeatDays,
                selectedHour: $selectedHour,
                selectedMinute: $selectedMinute,
                selectedAMPM: $selectedAMPM,
                isEditing: isEditing
            )
        }
        // WHY: Create/Edit Alarm is now a pushed destination, so it should use
        // the system back button and inline title instead of custom sheet chrome.
        .navigationTitle(isEditing ? "Edit Alarm" : "New Alarm")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .foregroundStyle(.orange)
                .font(.system(size: 16, weight: .semibold))
            }
        }
        .alert("Date Already Passed", isPresented: $showPastDateAlert) {
            Button("Change Date", role: .cancel) {}
        } message: {
            Text("The date you selected has already passed. Please pick a future date.")
        }
        .onAppear {
            if let id = editingAlarmID {
                let url = voiceURL(for: id)
                hasRecording = FileManager.default.fileExists(atPath: url.path)
                // ✅ Load scheduledDate for one-time and yearly
                if repeatType == "" {
                    if let item = AlarmService.shared.alarms.first(where: { $0.id.uuidString == id }),
                       let fireDate = item.fireDate {
                        scheduledDate = fireDate
                    }
                }
                recordingName = UserDefaults.standard.string(forKey: voiceNameKey(for: id)) ?? ""
                // ✅ Load sound — try alarm ID first, then group ID
                if let savedSound = UserDefaults.standard.string(forKey: "alarmSound_\(id)") {
                    selectedSound = savedSound
                } else if let groupID = AlarmService.shared.getGroupID(for: UUID(uuidString: id) ?? UUID()),
                          let savedSound = UserDefaults.standard.string(forKey: "alarmSound_\(groupID.uuidString)") {
                    selectedSound = savedSound
                }
                // ✅ Also check if selectedSound is a custom recording
                if selectedSound.hasPrefix("custom_voice_") || selectedSound.hasPrefix("alarm_voice_") {
                    let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                    let customURL = libraryURL.appendingPathComponent("Sounds/\(selectedSound)")
                    if FileManager.default.fileExists(atPath: customURL.path) {
                        hasRecording = true
                        let saved = UserDefaults.standard.array(forKey: "customRecordingsList") as? [[String: String]] ?? []
                        recordingName = saved.first(where: { $0["file"] == selectedSound })?["name"] ?? ""
                    } else {
                        // ✅ File missing — reset to default
                        selectedSound = "nokia.caf"
                        hasRecording = false
                        recordingName = ""
                    }
                } else if let id = editingAlarmID, hasRecording {
                    // ✅ Try to match alarm voice file to a custom recording by file
                    let saved = UserDefaults.standard.array(forKey: "customRecordingsList") as? [[String: String]] ?? []
                    let voiceFile = UserDefaults.standard.string(forKey: "voiceRecordingFile_\(id)") ?? ""
                    if let match = saved.first(where: { $0["file"] == voiceFile }) {
                        selectedSound = match["file"] ?? selectedSound
                        recordingName = match["name"] ?? recordingName
                    } else {
                        // ✅ Fallback — match by name
                        let voiceName = UserDefaults.standard.string(forKey: "voiceRecordingName_\(id)") ?? ""
                        if let match = saved.first(where: { $0["name"] == voiceName }) {
                            selectedSound = match["file"] ?? selectedSound
                            recordingName = match["name"] ?? recordingName
                        }
                    }
                }
                originalHour = selectedHour
                originalMinute = selectedMinute
                originalAMPM = selectedAMPM
                originalTitle = title
                originalSound = selectedSound
                originalRepeatDays = finalRepeatDays
                originalRepeatType = repeatType
                originalDayOfMonth = selectedDayOfMonth
                originalSnoozeEnabled = snoozeEnabled
                originalSnoozeDuration = snoozeDuration
                let resolvedID = UUID(uuidString: id) ?? UUID()
                let groupID = AlarmService.shared.getGroupID(for: resolvedID) ?? resolvedID
                // WHY: Calendar intent should follow the user's saved preference,
                // not the presence of orphaned calendar events left behind by older bugs.
                addToCalendar = AlarmService.shared.isCalendarEnabled(forGroup: groupID)
                originalAddToCalendar = addToCalendar
                originalScheduledDate = scheduledDate
            } else {
                try? FileManager.default.removeItem(at: tempRecordingURL)
                UserDefaults.standard.removeObject(forKey: "voiceRecordingName_temp")
                hasRecording = false
                recordingName = ""
                // ✅ Set scheduledDate for one-time calendar date
                if repeatType == "" && !Calendar.current.isDateInToday(selectedDate) {
                    scheduledDate = selectedDate
                }
            }
            loadCustomRecordings()
            if autoStartRecording, !didAutoStartRecording, !hasRecording {
                didAutoStartRecording = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    startRecording()
                }
            }
        }            .onDisappear {
            stopSoundPreview()
        }
        .alert("Rename Recording", isPresented: Binding(
            get: { editingRecordingFile != nil },
            set: { if !$0 { editingRecordingFile = nil } }
        )) {
            TextField("Recording name", text: $editingRecordingName)
            Button("Save") {
                if let file = editingRecordingFile {
                    renameCustomRecording(file: file, newName: editingRecordingName)
                }
                editingRecordingFile = nil
            }
            Button("Cancel", role: .cancel) {
                editingRecordingFile = nil
            }
        } message: {
            Text("Enter a new name for this recording")
        }
    }
    private func loadCustomRecordings() {
        let saved = UserDefaults.standard.array(forKey: "customRecordingsList") as? [[String: String]] ?? []
        customRecordings = saved.compactMap {
            guard let name = $0["name"], let file = $0["file"] else { return nil }
            return (name: name, file: file)
        }
    }

    private func saveCustomRecording(name: String, file: String) {
        var saved = UserDefaults.standard.array(forKey: "customRecordingsList") as? [[String: String]] ?? []
        saved.append(["name": name, "file": file])
        UserDefaults.standard.set(saved, forKey: "customRecordingsList")
        loadCustomRecordings()
        // ✅ Upload to iCloud
        AlarmService.shared.uploadRecordingToiCloud(fileName: file, name: name)
    }
    
    private func renameCustomRecording(file: String, newName: String) {
        var saved = UserDefaults.standard.array(forKey: "customRecordingsList") as? [[String: String]] ?? []
        if let index = saved.firstIndex(where: { $0["file"] == file }) {
            saved[index]["name"] = newName
            UserDefaults.standard.set(saved, forKey: "customRecordingsList")
            loadCustomRecordings()
        }
    }

    private func deleteCustomRecording(file: String) {
        var saved = UserDefaults.standard.array(forKey: "customRecordingsList") as? [[String: String]] ?? []
        saved.removeAll { $0["file"] == file }
        UserDefaults.standard.set(saved, forKey: "customRecordingsList")
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let url = libraryURL.appendingPathComponent("Sounds/\(file)")
        try? FileManager.default.removeItem(at: url)
        loadCustomRecordings()
    }

    private func saveAlarm() {
        stopSoundPreview()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let savedDate = fireDate
        let savedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Alarm" : title
        let savedRecordingName = recordingName
        let globalSnoozeEnabled = UserDefaults.standard.bool(forKey: "globalSnoozeEnabled")
        let globalSnoozeDuration = UserDefaults.standard.integer(forKey: "globalSnoozeDuration")
        let snoozeDur = globalSnoozeDuration > 0 ? globalSnoozeDuration : 5
        onSave(savedDate, savedTitle, globalSnoozeEnabled, TimeInterval(snoozeDur * 60), selectedSound, finalRepeatDays, addToCalendar)

        // ✅ Save selected sound for this alarm
        if let id = editingAlarmID {
            UserDefaults.standard.set(selectedSound, forKey: "alarmSound_\(id)")
            // ✅ Also save with group ID
            if let groupID = AlarmService.shared.getGroupID(for: UUID(uuidString: id) ?? UUID()) {
                UserDefaults.standard.set(selectedSound, forKey: "alarmSound_\(groupID.uuidString)")
            }
        }

        if hasRecording {
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let newAlarm = AlarmService.shared.alarms.first(where: {
                    guard let fd = $0.fireDate else { return false }
                    return abs(fd.timeIntervalSince(savedDate)) < 2
                }) {
                    let tempName = UserDefaults.standard.string(forKey: "voiceRecordingName_temp") ?? savedRecordingName
                    let tempFile = UserDefaults.standard.string(forKey: "voiceRecordingFile_temp") ?? ""
                    UserDefaults.standard.set(tempName, forKey: self.voiceNameKey(for: newAlarm.id.uuidString))
                    UserDefaults.standard.set(tempFile, forKey: "voiceRecordingFile_\(newAlarm.id.uuidString)")
                    UserDefaults.standard.removeObject(forKey: "voiceRecordingName_temp")
                    UserDefaults.standard.removeObject(forKey: "voiceRecordingFile_temp")
                }
            }
        }
        dismiss()
    }

    private func startRecording() {
        switch AVAudioApplication.shared.recordPermission {
        case .denied:
            NotificationCenter.default.post(name: NSNotification.Name("showMicPermission"), object: nil)
            return
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                guard granted else {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: NSNotification.Name("showMicPermission"), object: nil)
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.startRecordingSession()
                }
            }
            return
        default:
            break
        }
        startRecordingSession()
    }

    private func startRecordingSession() {
            DispatchQueue.main.async {
                try? FileManager.default.removeItem(at: self.tempRecordingURL)
                let settings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatLinearPCM),
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ]
                try? AVAudioSession.sharedInstance().setCategory(.record, mode: .default)
                try? AVAudioSession.sharedInstance().setActive(true)
                self.audioRecorder = try? AVAudioRecorder(url: self.tempRecordingURL, settings: settings)
                self.audioRecorder?.record()
                self.isRecording = true
            }
}

    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        isJustRecorded = true
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func playRecording() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        // ✅ If selected sound is a custom recording from list, play that
        if selectedSound.hasPrefix("custom_voice_") {
            let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            let url = libraryURL.appendingPathComponent("Sounds/\(selectedSound)")
            audioPlayer = try? AVAudioPlayer(contentsOf: url)
        } else if let id = editingAlarmID, !isJustRecorded {
            audioPlayer = try? AVAudioPlayer(contentsOf: voiceURL(for: id))
        } else {
            audioPlayer = try? AVAudioPlayer(contentsOf: tempRecordingURL)
        }
        audioPlayer?.play()
    }

    private func saveRecordingWithName() {
        let name = recordingName.isEmpty ? "Recording \(Date().formatted(.dateTime.hour().minute()))" : recordingName
        let fileName = "custom_voice_\(UUID().uuidString).caf"
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let destURL = libraryURL.appendingPathComponent("Sounds/\(fileName)")
        try? FileManager.default.copyItem(at: tempRecordingURL, to: destURL)
        // ✅ Only save to list if toggle is ON
        if saveToList {
            saveCustomRecording(name: name, file: fileName)
        }
        UserDefaults.standard.set(name, forKey: "voiceRecordingName_temp")
        UserDefaults.standard.set(fileName, forKey: "voiceRecordingFile_temp")
        hasRecording = true
        isJustRecorded = false
        recordingName = name
        selectedSound = fileName
        saveToList = false
    }

    private func deleteRecording() {
        try? FileManager.default.removeItem(at: tempRecordingURL)
        hasRecording = false; isJustRecorded = false; recordingName = ""
        UserDefaults.standard.removeObject(forKey: "voiceRecordingName_temp")
    }

    private func playSoundPreview(_ file: String) {
        stopSoundPreview()
        let fileName = (file as NSString).deletingPathExtension
        let fileExt = (file as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExt) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            soundPlayer = try AVAudioPlayer(contentsOf: url)
            soundPlayer?.play()
            playingSound = file
            let duration = soundPlayer?.duration ?? 3.0
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                if playingSound == file { playingSound = nil }
            }
        } catch {}
    }

    private func stopSoundPreview() {
        soundPlayer?.stop()
        soundPlayer = nil
        playingSound = nil
    }
    private func formatScheduledDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d yyyy"
        return f.string(from: date)
    }
}
