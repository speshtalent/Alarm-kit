import SwiftUI
import AVFoundation

struct AddTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var minutes: Int = 5
    @State private var seconds: Int = 0
    @State private var title: String = ""
    @State private var selectedSound = "nokia.caf"
    @State private var playingSound: String? = nil
    @State private var soundPlayer: AVAudioPlayer? = nil
    @State private var audioPlayer: AVAudioPlayer? = nil
    @State private var audioRecorder: AVAudioRecorder? = nil
    @State private var customRecordings: [(name: String, file: String)] = []
    @State private var showMyRecordings: Bool = false
    @State private var isRecording = false
    @State private var hasRecording = false
    @State private var isJustRecorded = false
    @State private var recordingName = ""
    @State private var saveToList: Bool = false

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

    var onStart: (TimeInterval, String, String) -> Void

    private var tempRecordingURL: URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let soundsURL = libraryURL.appendingPathComponent("Sounds")
        try? FileManager.default.createDirectory(at: soundsURL, withIntermediateDirectories: true)
        return soundsURL.appendingPathComponent("timer_voice_temp.caf")
    }

    var body: some View {
        ZStack {
            Color("AppBackground").ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color("SecondaryText").opacity(0.4))
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)

                    Text("New Timer")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("PrimaryText"))

                    // Time Picker card
                    ZStack {
                        RoundedRectangle(cornerRadius: 20).fill(Color("CardBackground"))
                        HStack(spacing: 0) {
                            Picker("Minutes", selection: $minutes) {
                                ForEach(0...179, id: \.self) { m in
                                    Text("\(m) min").tag(m)
                                }
                            }
                            .pickerStyle(.wheel).frame(maxWidth: .infinity)
                            Picker("Seconds", selection: $seconds) {
                                ForEach(0...59, id: \.self) { s in
                                    Text("\(s) sec").tag(s)
                                }
                            }
                            .pickerStyle(.wheel).frame(maxWidth: .infinity)
                        }
                        .colorScheme(colorScheme).padding(8)
                    }
                    .padding(.horizontal, 20)

                    // Title card
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(Color("CardBackground"))
                        HStack {
                            Image(systemName: "tag").foregroundStyle(.orange)
                            TextField("Enter timer name (optional)", text: $title)
                                .foregroundStyle(Color("PrimaryText")).tint(.orange)
                        }
                        .padding(16)
                    }
                    .frame(height: 54)
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
                            Text("Record your voice — it will play when timer fires")
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
                                        Button { playTempRecording() } label: {
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
                                        Button {
                                            try? FileManager.default.removeItem(at: tempRecordingURL)
                                            hasRecording = false; isJustRecorded = false; recordingName = ""
                                        } label: {
                                            Image(systemName: "trash.circle.fill").foregroundStyle(.red).font(.system(size: 34))
                                        }
                                    }
                                }
                            }
                            if hasRecording && !isJustRecorded {
                                HStack {
                                    Image(systemName: "waveform").foregroundStyle(.orange)
                                    Text(recordingName.isEmpty ? "Voice Recording" : recordingName)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color("PrimaryText"))
                                    Spacer()
                                    Button { playTempRecording() } label: {
                                        Image(systemName: "play.circle.fill")
                                            .foregroundStyle(.orange).font(.system(size: 22))
                                    }
                                    Button {
                                        hasRecording = false; isJustRecorded = false; recordingName = ""
                                        selectedSound = "nokia.caf"
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "mic.circle.fill").font(.system(size: 14))
                                            Text("Re-record").font(.system(size: 12, weight: .medium, design: .rounded))
                                        }
                                        .foregroundStyle(.red)
                                    }
                                }
                                .padding(10)
                                .background(Color("AppBackground"))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            // ✅ MY RECORDINGS — above ringtones
                            if !customRecordings.isEmpty {
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
                                                    .foregroundStyle(.orange).font(.system(size: 22))
                                            }
                                            Text(recording.name)
                                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                                .foregroundStyle(Color("PrimaryText"))
                                            Spacer()
                                            if selectedSound == recording.file {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.orange).font(.system(size: 18))
                                            }
                                        }
                                        .padding(.vertical, 8).padding(.horizontal, 8)
                                        .background(selectedSound == recording.file ? Color.orange.opacity(0.15) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedSound = recording.file
                                            hasRecording = false
                                            recordingName = recording.name
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 20)

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
                                            if selectedSound == sound.file && !selectedSound.hasPrefix("custom_voice_") {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.orange).font(.system(size: 18))
                                            }
                                        }
                                        .padding(.vertical, 10).padding(.horizontal, 8)
                                        .background(selectedSound == sound.file && !selectedSound.hasPrefix("custom_voice_") ? Color.orange.opacity(0.15) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedSound = sound.file
                                            hasRecording = false
                                            recordingName = ""
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

                    // Start Button
                    Button {
                        let duration = TimeInterval(minutes * 60 + seconds)
                        let timerTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Timer" : title
                        stopSoundPreview()
                        onStart(duration, timerTitle, selectedSound)
                        dismiss()
                    } label: {
                        Text("Start Timer")
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
        .onAppear { loadCustomRecordings() }
        .onDisappear { stopSoundPreview() }
    }

    private func loadCustomRecordings() {
        let saved = UserDefaults.standard.array(forKey: "customRecordingsList") as? [[String: String]] ?? []
        customRecordings = saved.compactMap {
            guard let name = $0["name"], let file = $0["file"] else { return nil }
            return (name: name, file: file)
        }
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

    private func playTempRecording() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        audioPlayer = try? AVAudioPlayer(contentsOf: tempRecordingURL)
        audioPlayer?.play()
    }

    private func saveRecordingWithName() {
        let name = recordingName.isEmpty ? "Recording \(Date().formatted(.dateTime.hour().minute()))" : recordingName
        let fileName = "custom_voice_\(UUID().uuidString).caf"
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let destURL = libraryURL.appendingPathComponent("Sounds/\(fileName)")
        try? FileManager.default.copyItem(at: tempRecordingURL, to: destURL)
        if saveToList {
            var saved = UserDefaults.standard.array(forKey: "customRecordingsList") as? [[String: String]] ?? []
            saved.append(["name": name, "file": fileName])
            UserDefaults.standard.set(saved, forKey: "customRecordingsList")
            AlarmService.shared.uploadRecordingToiCloud(fileName: fileName, name: name)
            loadCustomRecordings()
        }
        hasRecording = true
        isJustRecorded = false
        recordingName = name
        selectedSound = fileName
        saveToList = false
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
