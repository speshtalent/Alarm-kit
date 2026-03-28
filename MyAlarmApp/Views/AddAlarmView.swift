import SwiftUI
import AVFoundation

struct AddAlarmView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // ✅ Read 24hr setting
    @AppStorage("use24HourFormat") private var use24HourFormat: Bool = false

    @State private var selectedHour: Int
    @State private var selectedMinute: Int
    @State private var selectedDate: Date
    @State private var useSpecificDate: Bool
    @State private var title: String
    @State private var snoozeEnabled = true
    @State private var snoozeDuration = 5
    @State private var selectedSound = "nokia.caf"
    @State private var addToCalendar = true
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
    @State private var showPastTimeAlert = false

    private var editingAlarmID: String?
    var hideDateToggle: Bool = false

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

    init(preselectedDate: Date? = nil, editingItem: AlarmService.AlarmListItem? = nil, hideDateToggle: Bool = false, repeatDaysToLoad: Set<Int> = [], onSave: @escaping (Date, String, Bool, TimeInterval, String, Set<Int>) -> Void) {
        self.hideDateToggle = hideDateToggle
        self.onSave = onSave
        _repeatDays = State(initialValue: repeatDaysToLoad)

        if let item = editingItem, let fireDate = item.fireDate {
            _title = State(initialValue: item.label)
            _selectedDate = State(initialValue: fireDate)
            let hour24 = Calendar.current.component(.hour, from: fireDate)
            _selectedHour = State(initialValue: hour24)
            _selectedAMPM = State(initialValue: hour24 < 12 ? 0 : 1)
            _selectedMinute = State(initialValue: Calendar.current.component(.minute, from: fireDate))
            _useSpecificDate = State(initialValue: true)
            self.editingAlarmID = item.id.uuidString
        } else if let date = preselectedDate, !Calendar.current.isDateInToday(date) {
            _title = State(initialValue: "Alarm")
            _selectedDate = State(initialValue: date)
            let hour24 = Calendar.current.component(.hour, from: date)
            _selectedHour = State(initialValue: hour24)
            _selectedAMPM = State(initialValue: hour24 < 12 ? 0 : 1)
            _selectedMinute = State(initialValue: Calendar.current.component(.minute, from: date))
            _useSpecificDate = State(initialValue: true)
            self.editingAlarmID = nil
        } else {
            _title = State(initialValue: "Alarm")
            _selectedDate = State(initialValue: Date())
            let hour24 = Calendar.current.component(.hour, from: Date())
            _selectedHour = State(initialValue: hour24)
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
        if useSpecificDate {
            var components = Calendar.current.dateComponents(in: TimeZone.current, from: selectedDate)
            components.second = 0
            return Calendar.current.date(from: components) ?? selectedDate
        } else {
            // ✅ 24hr: selectedHour is already 0-23
            // 12hr: convert from 12hr + AMPM to 24hr
            let hour24: Int
            if use24HourFormat {
                hour24 = selectedHour
            } else {
                var h = selectedHour % 12
                if selectedAMPM == 1 { h += 12 }
                hour24 = h
            }
            var components = Calendar.current.dateComponents(in: TimeZone.current, from: Date())
            components.hour = hour24
            components.minute = selectedMinute
            components.second = 0
            var date = Calendar.current.date(from: components) ?? Date()
            if date <= Date() && repeatDays.isEmpty {
                date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
            }
            return date
        }
    }

    private var isEditing: Bool { editingAlarmID != nil }

    private var isTimeInPast: Bool {
        guard !useSpecificDate else {
            return fireDate <= Date() && repeatDays.isEmpty
        }
        let hour24: Int
        if use24HourFormat {
            hour24 = selectedHour
        } else {
            var h = selectedHour % 12
            if selectedAMPM == 1 { h += 12 }
            hour24 = h
        }
        var components = Calendar.current.dateComponents(in: TimeZone.current, from: Date())
        components.hour = hour24
        components.minute = selectedMinute
        components.second = 0
        let rawDate = Calendar.current.date(from: components) ?? Date()
        return rawDate <= Date() && repeatDays.isEmpty
    }

    private var repeatLabel: String {
        if repeatDays.isEmpty { return "Never" }
        if repeatDays.count == 7 { return "Every day" }
        if repeatDays == Set([2, 3, 4, 5, 6]) { return "Weekdays" }
        if repeatDays == Set([7, 1]) { return "Weekends" }
        let ordered = weekDays.filter { repeatDays.contains($0.value) }.map { $0.label }
        return ordered.joined(separator: ", ")
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

                    Text(isEditing ? "Edit Alarm" : "New Alarm")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("PrimaryText"))

                    Text("Rings at \(fireDate.formatted(date: useSpecificDate ? .abbreviated : .omitted, time: .shortened))")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)

                    // Set specific date card
                    if !hideDateToggle {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16).fill(Color("CardBackground"))
                            HStack {
                                Image(systemName: "calendar").foregroundStyle(.orange)
                                Text("Set specific date")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color("PrimaryText"))
                                Spacer()
                                Toggle("", isOn: $useSpecificDate).tint(.orange)
                            }
                            .padding(16)
                        }
                        .padding(.horizontal, 20)
                    }

                    // ✅ Picker card — changes based on 24hr setting
                    ZStack {
                        RoundedRectangle(cornerRadius: 20).fill(Color("CardBackground"))
                        if useSpecificDate {
                            DatePicker("", selection: $selectedDate,
                                in: Date().addingTimeInterval(60)...,
                                displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .colorScheme(colorScheme)
                            .padding(8)
                        } else if use24HourFormat {
                            // ✅ 24 hour picker — 0 to 23, no AM/PM
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
                            // ✅ 12 hour picker — 1 to 12 + AM/PM
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

                    // Repeat card
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(Color("CardBackground"))
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "repeat").foregroundStyle(.orange)
                                Text("Repeat")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color("PrimaryText"))
                                Spacer()
                                Text(repeatLabel)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.orange)
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
                                    } label: {
                                        Text(day.label)
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundStyle(isSelected ? .black : Color("SecondaryText"))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(isSelected ? Color.orange : Color("AppBackground"))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 20)

                    // Title card with header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Alarm name/label")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color("SecondaryText"))
                            .padding(.horizontal, 4)

                        ZStack {
                            RoundedRectangle(cornerRadius: 16).fill(Color("CardBackground"))
                            HStack {
                                Image(systemName: "tag").foregroundStyle(.orange)
                                TextField("Alarm name/label", text: $title)
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
                                        if let id = editingAlarmID {
                                            try? FileManager.default.removeItem(at: voiceURL(for: id))
                                            UserDefaults.standard.removeObject(forKey: voiceNameKey(for: id))
                                        }
                                        UserDefaults.standard.removeObject(forKey: "voiceRecordingName_temp")
                                    } label: {
                                        Text("Re-record")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .padding(10)
                                .background(Color("AppBackground"))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .transition(.move(edge: .top).combined(with: .opacity))
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
                                            Button {
                                                selectedSound = sound.file
                                            } label: {
                                                Text(sound.name)
                                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                                    .foregroundStyle(Color("PrimaryText"))
                                            }
                                            Spacer()
                                            if selectedSound == sound.file {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.orange)
                                                    .font(.system(size: 18))
                                            }
                                        }
                                        .padding(.vertical, 10)
                                        Divider()
                                    }
                                }
                            }
                            .frame(height: 200)
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 20)

                    // Snooze card
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(Color("CardBackground"))
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "moon.zzz.fill").foregroundStyle(.orange)
                                Text("Snooze")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color("PrimaryText"))
                                Spacer()
                                Toggle("", isOn: $snoozeEnabled).tint(.orange)
                            }
                            if snoozeEnabled {
                                Divider()
                                HStack {
                                    Text("Duration")
                                        .font(.system(size: 14, design: .rounded))
                                        .foregroundStyle(Color("SecondaryText"))
                                    Spacer()
                                    Stepper("\(snoozeDuration) min", value: $snoozeDuration, in: 1...30)
                                        .foregroundStyle(Color("PrimaryText"))
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                }
                            }
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
                            Toggle("", isOn: $addToCalendar).tint(.orange)
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 20)

                    Button {
                        if isTimeInPast {
                            showPastTimeAlert = true
                            return
                        }
                        saveAlarm()
                    } label: {
                        Text(isEditing ? "Update Alarm" : "Set Alarm")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
        .alert("Time Already Passed", isPresented: $showPastTimeAlert) {
            Button("Change Time", role: .cancel) {}
        } message: {
            Text("This time has already passed today. Please pick a future time or select repeat days to create a recurring alarm.")
        }
        .onAppear {
            if let id = editingAlarmID {
                let url = voiceURL(for: id)
                hasRecording = FileManager.default.fileExists(atPath: url.path)
                recordingName = UserDefaults.standard.string(forKey: voiceNameKey(for: id)) ?? ""
            } else {
                try? FileManager.default.removeItem(at: tempRecordingURL)
                UserDefaults.standard.removeObject(forKey: "voiceRecordingName_temp")
                hasRecording = false
                recordingName = ""
            }
        }
        .onDisappear {
            stopSoundPreview()
        }
    }

    private func saveAlarm() {
        stopSoundPreview()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let savedDate = fireDate
        let savedTitle = title
        let savedRecordingName = recordingName
        onSave(savedDate, savedTitle, snoozeEnabled, TimeInterval(snoozeDuration * 60), selectedSound, repeatDays)

        if hasRecording {
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let newAlarm = AlarmService.shared.alarms.first(where: {
                    guard let fd = $0.fireDate else { return false }
                    return abs(fd.timeIntervalSince(savedDate)) < 2
                }) {
                    let tempName = UserDefaults.standard.string(forKey: "voiceRecordingName_temp") ?? savedRecordingName
                    UserDefaults.standard.set(tempName, forKey: self.voiceNameKey(for: newAlarm.id.uuidString))
                    UserDefaults.standard.removeObject(forKey: "voiceRecordingName_temp")
                    print("✅ Voice name saved for alarm: \(newAlarm.id.uuidString)")
                }
            }
        }

        if addToCalendar {
            Task {
                await CalendarService.shared.addAlarmToCalendar(
                    title: savedTitle, date: savedDate,
                    alarmID: savedDate.timeIntervalSince1970.description
                )
            }
        }
        dismiss()
    }

    private func startRecording() {
        AVAudioApplication.requestRecordPermission { granted in
            guard granted else { return }
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
        if let id = editingAlarmID, !isJustRecorded {
            audioPlayer = try? AVAudioPlayer(contentsOf: voiceURL(for: id))
        } else {
            audioPlayer = try? AVAudioPlayer(contentsOf: tempRecordingURL)
        }
        audioPlayer?.play()
    }

    private func saveRecordingWithName() {
        UserDefaults.standard.set(recordingName, forKey: "voiceRecordingName_temp")
        hasRecording = true
        isJustRecorded = false
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
}
