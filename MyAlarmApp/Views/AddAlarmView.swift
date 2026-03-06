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

    // Voice recording
    @State private var isRecording = false
    @State private var hasRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioPlayer: AVAudioPlayer?

    let sounds: [(name: String, file: String)] = [
        (name: "Nokia", file: "nokia.caf"),
        (name: "1985 Ring", file: "1985_ring2.caf"),
        (name: "Sony", file: "sony.caf")
    ]

    var onSave: (Date, String, Bool, TimeInterval, String) -> Void

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
                    // Handle
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(white: 0.3))
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)

                    Text("New Alarm")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    // Fire time preview
                    Text("Rings at \(fireDate.formatted(date: useSpecificDate ? .abbreviated : .omitted, time: .shortened))")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)

                    // Toggle specific date
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

                    // Time Picker
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

                    // Title Field
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

                    // Voice Recording Section
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(white: 0.13))
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "mic.fill")
                                    .foregroundStyle(.orange)
                                Text("Voice Message")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                Spacer()
                                if hasRecording {
                                    Text("Recorded ✓")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(.green)
                                }
                            }
                            Divider().background(Color(white: 0.25))
                            Text("Record your voice — it will play once when alarm fires")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(.gray)

                            HStack(spacing: 12) {
                                // Record Button
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
                                    .background(isRecording ? Color.red : Color.orange)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }

                                // Play Button
                                if hasRecording {
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

                                    // Delete Button
                                    Button {
                                        deleteRecording()
                                    } label: {
                                        Image(systemName: "trash.circle.fill")
                                            .foregroundStyle(.red)
                                            .font(.system(size: 34))
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 20)

                    // Sound Picker
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

                    // Snooze Section
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

                    // Save Button
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
            hasRecording = FileManager.default.fileExists(atPath: recordingURL.path)
        }
    }

    // MARK: - Recording functions
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

    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        hasRecording = true
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func playRecording() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        audioPlayer = try? AVAudioPlayer(contentsOf: recordingURL)
        audioPlayer?.play()
    }

    private func deleteRecording() {
        try? FileManager.default.removeItem(at: recordingURL)
        hasRecording = false
    }
}
