import SwiftUI
import AVFoundation

struct AddAlarmView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedHour: Int = Calendar.current.component(.hour, from: Date())
    @State private var selectedMinute: Int = Calendar.current.component(.minute, from: Date())
    @State private var selectedDate: Date = Date()
    @State private var useSpecificDate: Bool = false
    @State private var title = "Alarm"
    @State private var snoozeEnabled = true
    @State private var snoozeDuration = 5
    @State private var selectedSound = "nokia.caf"

    // Voice recording states
    @State private var isRecording = false        // true = currently recording
    @State private var hasRecording = false       // true = recording saved
    @State private var isJustRecorded = false     // true = recording done, waiting to be named & saved
    @State private var recordingName = ""         // name user gives to recording
    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioPlayer: AVAudioPlayer?

    let sounds: [(name: String, file: String)] = [
        (name: "Nokia", file: "nokia.caf"),
        (name: "1985 Ring", file: "1985_ring2.caf"),
        (name: "Sony", file: "sony.caf")
    ]

    var onSave: (Date, String, Bool, TimeInterval, String) -> Void

    // Save recording to Library/Sounds/ so AlarmKit can find it
    private var recordingURL: URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let soundsURL = libraryURL.appendingPathComponent("Sounds")
        try? FileManager.default.createDirectory(at: soundsURL, withIntermediateDirectories: true)
        return soundsURL.appendingPathComponent("alarm_voice.caf")
    }

    private var fireDate: Date {
        if useSpecificDate {
            var components = Calendar.current.dateComponents(in: TimeZone.current, from: selectedDate)
            components.second = 0
            return Calendar.current.date(from: components) ?? selectedDate
        } else {
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
                    // Handle bar at top of sheet
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(white: 0.3))
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)

                    Text("New Alarm")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    // Shows what time alarm will ring
                    Text("Rings at \(fireDate.formatted(date: useSpecificDate ? .abbreviated : .omitted, time: .shortened))")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)

                    // Toggle to switch between hour/minute picker and date picker
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

                    // Time Picker — shows wheel picker for hour/minute or full date picker
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(white: 0.13))
                        if useSpecificDate {
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

                    // Alarm title text field
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
                                // Show green badge only when recording is fully saved
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
                                // Red when recording, orange when idle
                                .background(isRecording ? Color.red : Color.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

                            // MARK: Name + Save UI
                            // This slides in after user stops recording
                            // isJustRecorded = true means recording is done but not named/saved yet
                            if isJustRecorded {
                                VStack(alignment: .leading, spacing: 10) {

                                    Divider().background(Color(white: 0.25))

                                    // Text field for user to name their recording
                                    // e.g. "Morning Motivation", "Wake Up!", "Go to gym!"
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

                                        // Preview button — plays the recording so user can hear it
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
                                // Smooth slide down + fade in animation
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            // MARK: Saved Recording Row
                            // Shows after user taps Save — displays recording name
                            // with option to re-record
                            if hasRecording && !isJustRecorded {
                                HStack {
                                    Image(systemName: "waveform")
                                        .foregroundStyle(.orange)
                                    // Show name user gave, fallback to "Voice Recording"
                                    Text(recordingName.isEmpty ? "Voice Recording" : recordingName)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    // Re-record button — resets everything so user can record again
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
                    // Animate section when states change
                    .animation(.easeInOut(duration: 0.3), value: isJustRecorded)
                    .animation(.easeInOut(duration: 0.3), value: hasRecording)

                    // Sound Picker — choose Nokia, 1985 Ring or Sony
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

                    // Snooze toggle and duration stepper
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

                    // Set Alarm button — passes all data back to ContentView
                    Button {
                        onSave(fireDate, title, snoozeEnabled, TimeInterval(snoozeDuration * 60), selectedSound)
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
            // Check if recording already exists when screen opens
            hasRecording = FileManager.default.fileExists(atPath: recordingURL.path)
            // Load previously saved recording name
            recordingName = UserDefaults.standard.string(forKey: "voiceRecordingName") ?? ""
        }
    }

    // MARK: - Recording Functions

    // Asks microphone permission then starts recording
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

    // Stops recording and shows the name + save UI
    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        // Show name/save UI instead of directly marking as saved
        isJustRecorded = true
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    // Plays the recording for preview
    private func playRecording() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        audioPlayer = try? AVAudioPlayer(contentsOf: recordingURL)
        audioPlayer?.play()
    }

    // Saves the recording name to UserDefaults and marks as saved
    private func saveRecordingWithName() {
        // Save name so it persists even after app restarts
        UserDefaults.standard.set(recordingName, forKey: "voiceRecordingName")
        hasRecording = true
        isJustRecorded = false
    }

    // Deletes the recording file and resets all states
    private func deleteRecording() {
        try? FileManager.default.removeItem(at: recordingURL)
        hasRecording = false
        isJustRecorded = false
        recordingName = ""
        UserDefaults.standard.removeObject(forKey: "voiceRecordingName")
    }
}
