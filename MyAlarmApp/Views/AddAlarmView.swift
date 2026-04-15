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
    
    @State private var showMonthlySheet = false
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

    var onSave: (Date, String, Bool, TimeInterval, String, Set<Int>) -> Void

    init(
        preselectedDate: Date? = nil,
        initialTitle: String? = nil,
        editingItem: AlarmService.AlarmListItem? = nil,
        hideDateToggle: Bool = false,
        autoStartRecording: Bool = false,
        repeatDaysToLoad: Set<Int> = [],
        soundToLoad: String = "nokia.caf",
        onSave: @escaping (Date, String, Bool, TimeInterval, String, Set<Int>) -> Void
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
        _repeatDays = State(initialValue: monthsOnly.isEmpty && !repeatDaysToLoad.isEmpty && repeatDaysToLoad != Set([100]) && repeatDaysToLoad != Set([200]) ? repeatDaysToLoad : monthsOnly)

        // ✅ Detect repeatType from repeatDaysToLoad
        let hasMonths = repeatDaysToLoad.contains { $0 >= 101 && $0 <= 112 }
        let hasWeekDays = repeatDaysToLoad.contains { $0 >= 1 && $0 <= 7 }
        let isMonthlyGeneric = repeatDaysToLoad == Set([100])
        let isDayInMonth = repeatDaysToLoad.contains { $0 >= 1 && $0 <= 31 } && !hasWeekDays

        if isMonthlyGeneric || hasMonths || isDayInMonth {
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
            // ✅ Use current time not preselected date's time
            let now = Date()
            let hour24 = Calendar.current.component(.hour, from: now)
            let is24Hr = UserDefaults.standard.bool(forKey: "use24HourFormat")
            let hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24)
            _selectedHour = State(initialValue: is24Hr ? hour24 : hour12)
            _selectedAMPM = State(initialValue: hour24 < 12 ? 0 : 1)
            _selectedMinute = State(initialValue: Calendar.current.component(.minute, from: now))
            _useSpecificDate = State(initialValue: true)
            self.editingAlarmID = nil
            // ✅ Auto set monthly repeat with selected date's day and month
            let day = Calendar.current.component(.day, from: date)
            let month = Calendar.current.component(.month, from: date)
            _selectedDayOfMonth = State(initialValue: day)
            _repeatDays = State(initialValue: Set([100 + month]))
            _repeatType = State(initialValue: "monthly")
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

        let baseDate: Date
        if repeatType == "monthly" {
            // ✅ Build date from selectedDayOfMonth + selected month
            let month = repeatDays.filter { $0 >= 101 && $0 <= 112 }.min().map { $0 - 100 } ?? Calendar.current.component(.month, from: Date())
            let year = selectedYears.min() ?? Calendar.current.component(.year, from: Date())
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = selectedDayOfMonth
            baseDate = Calendar.current.date(from: comps) ?? selectedDate
        } else {
            if editingAlarmID != nil && Calendar.current.isDateInToday(selectedDate) {
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
        formatter.dateFormat = "h:mm a"
        let timeStr = formatter.string(from: date)
        let calendar = Calendar.current

        // ✅ Weekly
        if repeatType == "weekly" && !repeatDays.isEmpty {
            let ordered = weekDays.filter { repeatDays.contains($0.value) }.map { $0.label }
            let daysStr = ordered.joined(separator: ", ")
            return "Rings every \(daysStr) at \(timeStr)"
        }

        // ✅ Monthly with selected months
        let monthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        let selectedMonths = repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted()
        if repeatType == "monthly" && !selectedMonths.isEmpty {
            let monthsStr = selectedMonths.map { monthNames[$0 - 101] }.joined(separator: ", ")
            let yearsStr = selectedYears.sorted().map { "\($0)" }.joined(separator: ", ")
            if !selectedYears.isEmpty {
                return "Rings on day \(selectedDayOfMonth) of \(monthsStr) \(yearsStr) at \(timeStr)"
            }
            return "Rings on day \(selectedDayOfMonth) of \(monthsStr) at \(timeStr)"
        }

        // ✅ Monthly generic
        if repeatType == "monthly" {
            return "Rings every month on day \(selectedDayOfMonth) at \(timeStr)"
        }

        // ✅ Yearly with selected years
        let selectedYears = repeatDays.filter { $0 >= 2025 }.sorted()
        if repeatType == "yearly" && !selectedYears.isEmpty {
            let yearsStr = selectedYears.map { "\($0)" }.joined(separator: ", ")
            let f = DateFormatter(); f.dateFormat = "MMM d"
            return "Rings on \(f.string(from: date)) in \(yearsStr)"
        }

        // ✅ Yearly generic
        if repeatType == "yearly" {
            let f = DateFormatter(); f.dateFormat = "MMM d"
            return "Rings every year on \(f.string(from: date)) at \(timeStr)"
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
                   addToCalendar != originalAddToCalendar
    }

    private var isSpecificDateInPast: Bool {
        guard useSpecificDate else { return false }
        return fireDate <= Date() && repeatDays.isEmpty && repeatType == ""
    }

    private var repeatLabel: String {
        switch repeatType {
        case "monthly":
            let day = Calendar.current.component(.day, from: fireDate)
            return "Every month on \(day)"
        case "yearly":
            let f = DateFormatter()
            f.dateFormat = "MMM d"
            return "Every year on \(f.string(from: fireDate))"
        case "weekly":
            if repeatDays.isEmpty { return "Weekly" }
            if repeatDays.count == 7 { return "Every day" }
            if repeatDays == Set([2, 3, 4, 5, 6]) { return "Weekdays" }
            if repeatDays == Set([7, 1]) { return "Weekends" }
            let ordered = weekDays.filter { repeatDays.contains($0.value) }.map { $0.label }
            return ordered.joined(separator: ", ")
        default:
            return ""
        }
    }

    private var finalRepeatDays: Set<Int> {
        switch repeatType {
        case "monthly":
            var result: Set<Int> = []
            // ✅ Save selected months (101-112)
            let months = repeatDays.filter { $0 >= 101 && $0 <= 112 }
            result = months.isEmpty ? Set([100]) : months
            // ✅ Save selected day (1-31)
            result.insert(selectedDayOfMonth)
            // ✅ Save selected years
            result.formUnion(selectedYears)
            return result
        case "weekly": return repeatDays
        default: return []
        }
    }

    var body: some View {
        ZStack {
            Color("AppBackground").ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color("SecondaryText").opacity(0.4))
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)

                    HStack {
                        if isEditing {
                            Button { dismiss() } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(Color("SecondaryText").opacity(0.6))
                            }
                            .padding(.leading, 20)
                        }
                        Spacer()
                    }


                    Text(isEditing ? "Edit Alarm" : "New Alarm")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("PrimaryText"))

                    Text(ringsAtText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)



                    // Picker card
                    ZStack {
                        RoundedRectangle(cornerRadius: 20).fill(Color("CardBackground"))
                        if use24HourFormat {
                            HStack(spacing: 0) {
                                Picker("Hour", selection: $selectedHour) {
                                    ForEach(0...23, id: \.self) { h in
                                        Text(String(format: "%02d", h)).tag(h)
                                    }
                                }
                                .pickerStyle(.wheel).frame(maxWidth: .infinity)
                                Text(":").font(.system(size: 24, weight: .bold)).foregroundStyle(.orange)
                                Picker("Minute", selection: $selectedMinute) {
                                    ForEach(0...59, id: \.self) { m in
                                        Text(String(format: "%02d", m)).tag(m)
                                    }
                                }
                                .pickerStyle(.wheel).frame(maxWidth: .infinity)
                            }
                            .colorScheme(colorScheme).padding(8)
                        } else {
                            HStack(spacing: 0) {
                                Picker("Hour", selection: $selectedHour) {
                                    ForEach(1...12, id: \.self) { h in
                                        Text(String(format: "%d", h)).tag(h)
                                    }
                                }
                                .pickerStyle(.wheel).frame(maxWidth: .infinity)
                                Text(":").font(.system(size: 24, weight: .bold)).foregroundStyle(.orange)
                                Picker("Minute", selection: $selectedMinute) {
                                    ForEach(0...59, id: \.self) { m in
                                        Text(String(format: "%02d", m)).tag(m)
                                    }
                                }
                                .pickerStyle(.wheel).frame(maxWidth: .infinity)
                                Picker("AM/PM", selection: $selectedAMPM) {
                                    Text("AM").tag(0)
                                    Text("PM").tag(1)
                                }
                                .pickerStyle(.wheel).frame(maxWidth: 70)
                            }
                            .colorScheme(colorScheme).padding(8)
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
                                    let isSelected = repeatDays.contains(day.value)
                                    Button {
                                        if isSelected {
                                            repeatDays.remove(day.value)
                                        } else {
                                            repeatDays.insert(day.value)
                                        }
                                        repeatType = repeatDays.isEmpty ? (repeatType == "monthly" ? "monthly" : "") : "weekly"
                                    } label: {
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
                            Button {
                                if repeatType == "monthly" {
                                    showMonthlySheet = true
                                } else {
                                    repeatType = "monthly"
                                    showMonthlySheet = true
                                }
                            } label: {
                                HStack {
                                    Text("Date / Monthly / Yearly")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(repeatType == "monthly" ? .black : Color("SecondaryText"))
                                    Spacer()
                                    if repeatType == "monthly" {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.black)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .background(repeatType == "monthly" ? Color.orange : Color("AppBackground"))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .opacity(repeatType == "weekly" ? 0.3 : 1.0)
                            .disabled(repeatType == "weekly")
                            if repeatType == "monthly" && !repeatDays.isEmpty {
                                let monthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
                                let months = repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted().map { monthNames[$0 - 101] }
                                let years = selectedYears.sorted().map { String(format: "%d", $0) }
                                if !months.isEmpty {
                                    let yearText = years.isEmpty ? "" : " · \(years.joined(separator: ", "))"
                                    Text("Day \(selectedDayOfMonth) of \(months.joined(separator: ", "))\(yearText)")
                                        .font(.system(size: 13, design: .rounded))
                                        .foregroundStyle(Color("SecondaryText"))
                                }
                            }
                        }
                        .padding(16)
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
                                        HStack(spacing: 4) {
                                            Image(systemName: "mic.circle.fill")
                                                .font(.system(size: 14))
                                            Text("Re-record")
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                        }
                                        .foregroundStyle(.red)
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
                                        let status = EKEventStore.authorizationStatus(for: .event)
                                        if status == .denied {
                                            addToCalendar = false
                                            NotificationCenter.default.post(name: NSNotification.Name("showCalendarPermission"), object: nil)
                                        } else if status == .notDetermined {
                                            Task {
                                                await CalendarService.shared.requestPermissionIfNeeded()
                                                let newStatus = EKEventStore.authorizationStatus(for: .event)
                                                await MainActor.run {
                                                    if newStatus != .fullAccess {
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
        .sheet(isPresented: $showMonthlySheet) {
            MonthlyRepeatSheet(selectedDay: $selectedDayOfMonth, selectedMonths: $repeatDays, selectedYears: $selectedYears)
        }

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
                // ✅ Check if this alarm has a calendar event
                if let item = AlarmService.shared.alarms.first(where: { $0.id.uuidString == id }),
                   let fireDate = item.fireDate {
                    let key = fireDate.timeIntervalSince1970.description
                    let map = UserDefaults.standard.dictionary(forKey: "calendarEventMap") as? [String: String] ?? [:]
                    addToCalendar = map[key] != nil
                }
                originalAddToCalendar = addToCalendar
            } else {
                try? FileManager.default.removeItem(at: tempRecordingURL)
                UserDefaults.standard.removeObject(forKey: "voiceRecordingName_temp")
                hasRecording = false
                recordingName = ""
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
        onSave(savedDate, savedTitle, globalSnoozeEnabled, TimeInterval(snoozeDur * 60), selectedSound, finalRepeatDays)

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
        if addToCalendar {
            Task {
                // ✅ Remove old calendar event if editing
                if let id = editingAlarmID,
                   let item = AlarmService.shared.alarms.first(where: { $0.id.uuidString == id }),
                   let fireDate = item.fireDate {
                    let key = fireDate.timeIntervalSince1970.description
                    CalendarService.shared.removeAlarmFromCalendar(alarmID: key)
                }
                // ✅ Wait for alarms to be scheduled first
                try? await Task.sleep(nanoseconds: 500_000_000)
                let groupID = AlarmService.shared.alarmGroups.first(where: {
                    $0.label == savedTitle
                })?.id
                let alarmIDs = groupID.flatMap { AlarmService.shared.getAlarmIDs(forGroup: $0) } ?? []
                
                if alarmIDs.isEmpty {
                    // ✅ Single alarm — add once
                    _ = await CalendarService.shared.addAlarmToCalendar(
                        title: savedTitle, date: savedDate,
                        alarmID: savedDate.timeIntervalSince1970.description
                    )
                } else {
                    // ✅ Multiple alarms (monthly/weekly) — add each one with recurrence
                    for alarmID in alarmIDs {
                        if let fireDate = AlarmService.shared.alarms.first(where: { $0.id == alarmID })?.fireDate {
                            // ✅ Get weekday for this alarm (1=Sun, 2=Mon...7=Sat)
                            let weekday = Calendar.current.component(.weekday, from: fireDate)
                            let isWeekly = finalRepeatDays.contains { $0 >= 1 && $0 <= 7 }
                            _ = await CalendarService.shared.addAlarmToCalendar(
                                title: savedTitle, date: fireDate,
                                alarmID: fireDate.timeIntervalSince1970.description,
                                weekday: isWeekly ? weekday : nil
                            )
                        }
                    }
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
    // MARK: - Monthly Repeat Sheet
    struct MonthlyRepeatSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Binding var selectedDay: Int
        @Binding var selectedMonths: Set<Int>
        @Binding var selectedYears: Set<Int>

        private let monthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        private let currentYear = Calendar.current.component(.year, from: Date())
        @State private var showNoMonthAlert: Bool = false

        private var maxDaysForSelectedMonth: Int {
            let selectedMonthNumbers = selectedMonths.filter { $0 >= 101 && $0 <= 112 }.map { $0 - 100 }
            if selectedMonthNumbers.isEmpty { return 31 }
            let maxDays = selectedMonthNumbers.map { month -> Int in
                switch month {
                case 2: return 29
                case 4, 6, 9, 11: return 30
                default: return 31
                }
            }.max() ?? 31
            return maxDays
        }

        var body: some View {
            ZStack {
                Color("AppBackground").ignoresSafeArea()
                VStack(spacing: 0) {
                    ZStack {
                        HStack {
                            Button { dismiss() } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(Color("SecondaryText").opacity(0.6))
                            }
                            .padding(.leading, 20)
                            Spacer()
                        }
                        Text("Date / Monthly / Yearly")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color("PrimaryText"))
                    }
                    .padding(.top, 12)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color("SecondaryText").opacity(0.4))
                        .frame(width: 40, height: 5)
                        .padding(.bottom, 16)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("PrimaryText"))
                        .padding(.bottom, 4)

                    // ✅ Summary text
                    let monthNames2 = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
                    let selectedMonthNames = selectedMonths.filter { $0 >= 101 && $0 <= 112 }.sorted().map { monthNames2[$0 - 101] }
                    let selectedYearNames = selectedYears.sorted().map { "\($0)" }

                    Text("Day \(selectedDay) · \(selectedMonthNames.isEmpty ? "Every month" : selectedMonthNames.joined(separator: ", "))\(selectedYearNames.isEmpty ? "" : " · \(selectedYearNames.joined(separator: ", "))")")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)
                        .padding(.bottom, 16)

                    ScrollView {
                        VStack(spacing: 20) {
                            // Day picker — dynamic based on selected months
                            ZStack {
                                RoundedRectangle(cornerRadius: 16).fill(Color("CardBackground"))
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Day of Month")
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color("PrimaryText"))
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                                        ForEach(1...31, id: \.self) { day in
                                            let currentDay = Calendar.current.component(.day, from: Date())
                                            let currentMonthNow = Calendar.current.component(.month, from: Date())
                                            let noYearSelected = selectedYears.isEmpty
                                            let onlyCurrentMonthSelected = selectedMonths == Set([100 + currentMonthNow])
                                            let isPastDay = noYearSelected && onlyCurrentMonthSelected && day < currentDay
                                            let isAvailable = day <= maxDaysForSelectedMonth && !isPastDay
                                            Button {
                                                if isAvailable { selectedDay = day }
                                            } label: {
                                                ZStack {
                                                    Circle()
                                                        .fill(
                                                            (!isAvailable || isPastDay) ? Color.gray.opacity(0.15) :
                                                            selectedDay == day ? Color.orange : Color("AppBackground")
                                                        )
                                                        .frame(width: 36, height: 36)
                                                    Text("\(day)")
                                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                        .foregroundStyle(
                                                            (!isAvailable || isPastDay) ? Color.gray.opacity(0.4) :
                                                            selectedDay == day ? .black : Color("PrimaryText")
                                                        )
                                                }
                                            }
                                            .disabled(!isAvailable)
                                            .opacity(day <= maxDaysForSelectedMonth ? 1.0 : 0.0)
                                            .scaleEffect(day <= maxDaysForSelectedMonth ? 1.0 : 0.1)
                                            .animation(.spring(response: 0.4, dampingFraction: 0.55), value: maxDaysForSelectedMonth)
                                        }
                                    }
                                    .id(selectedMonths)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                                        removal: .scale(scale: 0.9).combined(with: .opacity)
                                    ))
                                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: selectedMonths)
                                }

                                .padding(16)
                            }
                            .padding(.horizontal, 20)

                            // Month selector
                            ZStack {
                                RoundedRectangle(cornerRadius: 16).fill(Color("CardBackground"))
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Select Months")
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundStyle(Color("PrimaryText"))
                                        Spacer()
                                        Text("Required")
                                            .font(.system(size: 12, design: .rounded))
                                            .foregroundStyle(.orange)
                                    }
                                    Text("Select a month for the alarm to ring")
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundStyle(Color("SecondaryText"))
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                                        ForEach(0..<12, id: \.self) { i in
                                            let monthValue = 101 + i
                                            let isSelected = selectedMonths.contains(monthValue)
                                            // ✅ No year selected = current year = gray out past months
                                            let currentMonth = Calendar.current.component(.month, from: Date())
                                            let noYearSelected = selectedYears.isEmpty
                                            let isPastMonth = noYearSelected && (i + 1) < currentMonth
                                            Button {
                                                if !isPastMonth {
                                                    if isSelected {
                                                        selectedMonths.remove(monthValue)
                                                    } else {
                                                        selectedMonths.insert(monthValue)
                                                    }
                                                    if selectedDay > maxDaysForSelectedMonth {
                                                        selectedDay = maxDaysForSelectedMonth
                                                    }
                                                }
                                            } label: {
                                                Text(monthNames[i])
                                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                                    .foregroundStyle(
                                                        isPastMonth ? Color("SecondaryText").opacity(0.3) :
                                                        isSelected ? .black : Color("SecondaryText")
                                                    )
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 10)
                                                    .background(
                                                        isPastMonth ? Color.clear :
                                                        isSelected ? Color.orange : Color("AppBackground")
                                                    )
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                            }
                                            .disabled(isPastMonth)
                                        }
                                    }
                                }
                                .padding(16)
                            }
                            .padding(.horizontal, 20)

                            // Year selector (optional)
                            ZStack {
                                RoundedRectangle(cornerRadius: 16).fill(Color("CardBackground"))
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Select Years")
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundStyle(Color("PrimaryText"))
                                        Spacer()
                                        Text("Optional")
                                            .font(.system(size: 12, design: .rounded))
                                            .foregroundStyle(Color("SecondaryText"))
                                    }
                                    Text("If no year is selected, rings every month")
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundStyle(Color("SecondaryText"))
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                                        ForEach((currentYear + 1)...(currentYear + 10), id: \.self) { year in
                                            let isSelected = selectedYears.contains(year)
                                            Button {
                                                if isSelected {
                                                    selectedYears.remove(year)
                                                } else {
                                                    selectedYears.insert(year)
                                                }
                                            } label: {
                                                Text(String(format: "%d", year))
                                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                                    .foregroundStyle(isSelected ? .black : Color("SecondaryText"))
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 10)
                                                    .background(isSelected ? Color.orange : Color("AppBackground"))
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                            }
                                        }
                                    }
                                }
                                .padding(16)
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    Button {
                        if selectedMonths.isEmpty {
                            showNoMonthAlert = true
                        } else {
                            dismiss()
                        }
                    } label: {
                        Text("Done")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .alert("Select a Month", isPresented: $showNoMonthAlert) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("Please select at least one month to continue.")
                    }
                }
            }
        }
    }
}
