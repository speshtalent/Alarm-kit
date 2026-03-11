import SwiftUI
import AVFoundation

struct AddAlarmView: View {
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Time & Date States
    @State private var selectedHour: Int = Calendar.current.component(.hour, from: Date())
    @State private var selectedMinute: Int = Calendar.current.component(.minute, from: Date())
    @State private var selectedDate: Date = Date()
    // when true — shows full date picker instead of hour/minute wheel
    @State private var useSpecificDate: Bool = false
    
    // MARK: - Alarm Settings States
    @State private var title = "Alarm"
    @State private var snoozeEnabled = true
    @State private var snoozeDuration = 5
    @State private var selectedSound = "nokia.caf"
    // when true — alarm will also be added to iPhone Calendar app
    @State private var addToCalendar = false

    // MARK: - Voice Recording States
    @State private var isRecording = false        // true = currently recording
    @State private var hasRecording = false       // true = recording saved
    @State private var isJustRecorded = false     // true = recording done, waiting to be named & saved
    @State private var recordingName = ""         // name user gives to recording
    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioPlayer: AVAudioPlayer?

    // MARK: - Sound Options
    let sounds: [(name: String, file: String)] = [
        (name: "Nokia", file: "nokia.caf"),
        (name: "1985 Ring", file: "1985_ring2.caf"),
        (name: "Sony", file: "sony.caf")
    ]

    // callback to ContentView — called when user taps Set Alarm
    var onSave: (Date, String, Bool, TimeInterval, String) -> Void

    // MARK: - Recording URL
    // Save recording to Library/Sounds/ so AlarmKit can find it at runtime
    private var recordingURL: URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let soundsURL = libraryURL.appendingPathComponent("Sounds")
        try? FileManager.default.createDirectory(at: soundsURL, withIntermediateDirectories: true)
        return soundsURL.appendingPathComponent("alarm_voice.caf")
    }

    // MARK: - Computed Fire Date
    // calculates the exact date/time the alarm will fire
    private var fireDate: Date {
        if useSpecificDate {
            // use the full date picker value
            var components = Calendar.current.dateComponents(in: TimeZone.current, from: selectedDate)
            components.second = 0
            return Calendar.current.date(from: components) ?? selectedDate
        } else {
            // use hour/minute wheel picker — if time already passed today, set for tomorrow
            var components = Calendar.current.dateComponents(in: TimeZone.current, from: Date())
            components.hour = selectedHour
            components.minute = selectedMinute
            components.second = 0
            var date = Calendar.current.date(from: components) ?? Date()
            if date <= Date() {
                date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
            }
            return date
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.09).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    
                    // MARK: - Handle Bar
                    // visual indicator that this is a draggable sheet
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(white: 0.3))
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)

                    // MARK: - Title
                    Text("New Alarm")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    // MARK: - Rings At Label
                    // shows user exactly when alarm will fire based on their selection
                    Text("Rings at \(fireDate.formatted(date: useSpecificDate ? .abbreviated : .omitted, time: .shortened))")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)

                    // MARK: - Specific Date Toggle
                    // switches between hour/minute wheel and full date picker
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(white: 0.13))
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(.orange)
                            Text("Set specific date")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer()
                            Toggle("", isOn: $useSpecificDate)
                                .tint(.orange)
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 20)

                    // MARK: - Time Picker
                    // shows wheel picker for hour/minute OR full date picker
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(white: 0.13))
                        if useSpecificDate {
                            // full date + time picker
                            DatePicker(
                                "",
                                selection: $selectedDate,
                                in: Date().addingTimeInterval(60)...,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .colorScheme(.dark)
                            .padding(8)
                        } else {
                            // hour and minute wheel pickers side by side
                            HStack(spacing: 0) {
                                Picker("Hour", selection: $selectedHour) {
                                    ForEach(0...23, id: \.self) { h in
                                        Text(String(format: "%02d", h)).tag(h)
                                            .foregroundStyle(.white)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(maxWidth: .infinity)

                                Text(":")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.orange)

                                Picker("Minute", selection: $selectedMinute) {
                                    ForEach(0...59, id: \.self) { m in
                                        Text(String(format: "%02d", m)).tag(m)
                                            .foregroundStyle(.white)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(maxWidth: .infinity)
                            }
                            .colorScheme(.dark)
                            .padding(8)
                        }
                    }
                    .padding(.horizontal, 20)

                    // MARK: - Alarm Title Field
                    // user can give their alarm a custom name
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(white: 0.13))
                        HStack {
                            Image(systemName: "tag").foregroundStyle(.orange)
                            TextField("Alarm title", text: $title)
                                .foregroundStyle(.white)
                                .tint(.orange)
                        }
                        .padding(16)
                    }
                    .frame(height: 54)
                    .padding(.horizontal, 20)

                    // MARK: - Voice Recording Section
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(white: 0.13))
                        VStack(alignment: .leading, spacing: 12) {

                            // Header row
                            HStack {
                                Image(systemName: "mic.fill")
                                    .foregroundStyle(.orange)
                                Text("Voice Message")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                Spacer()
                                // show green badge only when recording is fully saved
                                if hasRecording {
                                    Text("Recorded ✓")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.green)
                                }
                            }

                            Divider().background(Color(white: 0.25))

                            Text("Record your voice — it will play when alarm fires")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(.gray)

                            // Record / Stop button
                            // tapping toggles between start and stop recording
                            Button {
                                isRecording ? stopRecording() : startRecording()
                            } label: {
                                HStack {
                                    Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                    Text(isRecording ? "Stop" : "Record")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                // red when recording, orange when idle
                                .background(isRecording ? Color.red : Color.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            // MARK: Name + Save UI
                            // slides in after user stops recording
                            // isJustRecorded = true means recording done but not named/saved yet
                            if isJustRecorded {
                                VStack(alignment: .leading, spacing: 10) {

                                    Divider().background(Color(white: 0.25))

                                    // text field for user to name their recording
                                    HStack {
                                        Image(systemName: "pencil")
                                            .foregroundStyle(.orange)
                                        TextField("Name your recording...", text: $recordingName)
                                            .foregroundStyle(.white)
                                            .tint(.orange)
                                    }
                                    .padding(10)
                                    .background(Color(white: 0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                    HStack(spacing: 12) {

                                        // Preview button — plays recording so user can hear it
                                        Button {
                                            playRecording()
                                        } label: {
                                            HStack {
                                                Image(systemName: "play.circle.fill")
                                                Text("Preview")
                                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            }
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .background(Color(white: 0.25))
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }

                                        // Save button — saves name to UserDefaults
                                        // hides this UI and shows saved recording row
                                        Button {
                                            saveRecordingWithName()
                                        } label: {
                                            HStack {
                                                Image(systemName: "checkmark.circle.fill")
                                                Text("Save")
                                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            }
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .background(Color.green)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }

                                        // Delete button — discards recording without saving
                                        Button {
                                            deleteRecording()
                                        } label: {
                                            Image(systemName: "trash.circle.fill")
                                                .foregroundStyle(.red)
                                                .font(.system(size: 34))
                                        }
                                    }
                                }
                                // smooth slide down + fade in animation
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            // MARK: Saved Recording Row
                            // shows after user taps Save — displays recording name
                            if hasRecording && !isJustRecorded {
                                HStack {
                                    Image(systemName: "waveform")
                                        .foregroundStyle(.orange)
                                    // show name user gave, fallback to "Voice Recording"
                                    Text(recordingName.isEmpty ? "Voice Recording" : recordingName)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    // re-record button — resets so user can record again
                                    Button {
                                        hasRecording = false
                                        isJustRecorded = false
                                        recordingName = ""
                                        UserDefaults.standard.removeObject(forKey: "voiceRecordingName")
                                    } label: {
                                        Text("Re-record")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .padding(10)
                                .background(Color(white: 0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 20)
                    // animate section when states change
                    .animation(.easeInOut(duration: 0.3), value: isJustRecorded)
                    .animation(.easeInOut(duration: 0.3), value: hasRecording)

                    // MARK: - Sound Picker
                    // user picks which sound plays when alarm fires
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(white: 0.13))
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "bell.fill")
                                    .foregroundStyle(.orange)
                                Text("Sound")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            Divider().background(Color(white: 0.25))
                            ForEach(sounds, id: \.file) { sound in
                                Button {
                                    selectedSound = sound.file
                                } label: {
                                    HStack {
                                        Text(sound.name)
                                            .font(.system(size: 15, weight: .medium, design: .rounded))
                                            .foregroundStyle(.white)
                                        Spacer()
                                        // checkmark on currently selected sound
                                        if selectedSound == sound.file {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 20)

                    // MARK: - Snooze Section
                    // toggle snooze on/off and set snooze duration in minutes
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(white: 0.13))
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "moon.zzz.fill")
                                    .foregroundStyle(.orange)
                                Text("Snooze")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                Spacer()
                                Toggle("", isOn: $snoozeEnabled)
                                    .tint(.orange)
                            }
                            if snoozeEnabled {
                                Divider().background(Color(white: 0.25))
                                HStack {
                                    Text("Duration")
                                        .font(.system(size: 14, design: .rounded))
                                        .foregroundStyle(.gray)
                                    Spacer()
                                    Stepper("\(snoozeDuration) min", value: $snoozeDuration, in: 1...30)
                                        .foregroundStyle(.white)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                }
                            }
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 20)

                    // MARK: - Add to Calendar Toggle
                    // when ON — alarm will also be saved as event in iPhone Calendar app
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(white: 0.13))
                        HStack {
                            // calendar icon
                            Image(systemName: "calendar.badge.plus")
                                .foregroundStyle(.orange)
                            Text("Add to Calendar")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer()
                            // toggle — bound to addToCalendar state
                            Toggle("", isOn: $addToCalendar)
                                .tint(.orange)
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 20)

                    // MARK: - Set Alarm Button
                    // tapping this saves the alarm and optionally adds to iPhone Calendar
                    Button {
                        // Step 1 — save alarm in app (existing behaviour)
                        onSave(fireDate, title, snoozeEnabled, TimeInterval(snoozeDuration * 60), selectedSound)

                        // Step 2 — if user turned on "Add to Calendar" toggle
                        // add this alarm as an event in iPhone Calendar app
                        if addToCalendar {
                            let savedDate = fireDate
                            let savedTitle = title
                            Task {
                                await CalendarService.shared.addAlarmToCalendar(
                                    title: savedTitle,
                                    date: savedDate,
                                    alarmID: savedDate.timeIntervalSince1970.description
                                )
                            }
                        }

                        // Step 3 — close the Add Alarm sheet
                        dismiss()
                    } label: {
                        Text("Set Alarm")
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
        .onAppear {
            // check if recording already exists when screen opens
            hasRecording = FileManager.default.fileExists(atPath: recordingURL.path)
            // load previously saved recording name
            recordingName = UserDefaults.standard.string(forKey: "voiceRecordingName") ?? ""
        }
    }

    // MARK: - Recording Functions

    // asks microphone permission then starts recording
    private func startRecording() {
        AVAudioApplication.requestRecordPermission { granted in
            guard granted else { return }
            DispatchQueue.main.async {
                let settings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatLinearPCM),
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ]
                try? AVAudioSession.sharedInstance().setCategory(.record, mode: .default)
                try? AVAudioSession.sharedInstance().setActive(true)
                audioRecorder = try? AVAudioRecorder(url: recordingURL, settings: settings)
                audioRecorder?.record()
                isRecording = true
            }
        }
    }

    // stops recording and shows the name + save UI
    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        // show name/save UI instead of directly marking as saved
        isJustRecorded = true
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // plays the recording for preview
    private func playRecording() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        audioPlayer = try? AVAudioPlayer(contentsOf: recordingURL)
        audioPlayer?.play()
    }

    // saves the recording name to UserDefaults and marks as saved
    private func saveRecordingWithName() {
        // save name so it persists even after app restarts
        UserDefaults.standard.set(recordingName, forKey: "voiceRecordingName")
        hasRecording = true
        isJustRecorded = false
    }

    // deletes the recording file and resets all states
    private func deleteRecording() {
        try? FileManager.default.removeItem(at: recordingURL)
        hasRecording = false
        isJustRecorded = false
        recordingName = ""
        UserDefaults.standard.removeObject(forKey: "voiceRecordingName")
    }
}
