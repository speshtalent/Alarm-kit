import SwiftUI
import CoreData

struct AddAlarmView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @State private var selectedHour: Int = Calendar.current.component(.hour, from: Date())
    @State private var selectedMinute: Int = Calendar.current.component(.minute, from: Date())
    @State private var selectedDate: Date = Date()
    @State private var useSpecificDate: Bool = false
    @State private var title = "Alarm"
    @State private var snoozeEnabled = true
    @State private var snoozeDuration = 5

    @State private var soundSource: SoundSource = .system
    @State private var selectedRecordingID: UUID?
    @State private var showRecordingsManager = false

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: #keyPath(VoiceRecording.createdAt), ascending: false)],
        animation: .default
    )
    private var recordings: FetchedResults<VoiceRecording>

    var onSave: (Date, String, Bool, TimeInterval, AlarmSoundChoice) -> Void

    enum SoundSource: String, CaseIterable {
        case system = "System"
        case recording = "Recording"
    }

    private var fireDate: Date {
        if useSpecificDate {
            var components = Calendar.current.dateComponents(in: TimeZone.current, from: selectedDate)
            components.second = 0
            return Calendar.current.date(from: components) ?? selectedDate
        }

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

    private var canSave: Bool {
        switch soundSource {
        case .system:
            return true
        case .recording:
            return selectedRecordingID != nil
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.09).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(white: 0.3))
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)

                    Text("New Alarm")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Rings at \(fireDate.formatted(date: useSpecificDate ? .abbreviated : .omitted, time: .shortened))")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange)

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
                                    ForEach(0...23, id: \.self) { hour in
                                        Text(String(format: "%02d", hour)).tag(hour)
                                            .foregroundStyle(.white)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(maxWidth: .infinity)

                                Text(":")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.orange)

                                Picker("Minute", selection: $selectedMinute) {
                                    ForEach(0...59, id: \.self) { minute in
                                        Text(String(format: "%02d", minute)).tag(minute)
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

                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(white: 0.13))
                        HStack {
                            Image(systemName: "tag")
                                .foregroundStyle(.orange)
                            TextField("Alarm title", text: $title)
                                .foregroundStyle(.white)
                                .tint(.orange)
                        }
                        .padding(16)
                    }
                    .frame(height: 54)
                    .padding(.horizontal, 20)

                    soundSelectionSection

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

                    Button {
                        let finalChoice: AlarmSoundChoice
                        switch soundSource {
                        case .system:
                            finalChoice = .systemDefault
                        case .recording:
                            finalChoice = .customRecording(selectedRecordingID ?? UUID())
                        }

                        onSave(fireDate, title, snoozeEnabled, TimeInterval(snoozeDuration * 60), finalChoice)
                        dismiss()
                    } label: {
                        Text("Set Alarm")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(canSave ? .orange : .gray)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    .disabled(!canSave)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
        .sheet(isPresented: $showRecordingsManager) {
            VoiceRecordingsView(context: context)
                .environment(\.managedObjectContext, context)
        }
    }

    private var soundSelectionSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.13))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.orange)
                    Text("Alarm Tone")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Manage") {
                        showRecordingsManager = true
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
                }

                Picker("Sound Source", selection: $soundSource) {
                    ForEach(SoundSource.allCases, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)

                if soundSource == .system {
                    HStack {
                        Text("System Default (Nokia)")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                    .padding(.top, 2)
                } else {
                    if recordings.isEmpty {
                        Text("No voice recordings found. Create one using Manage.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.gray)
                            .padding(.top, 2)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(recordings, id: \.id) { recording in
                                Button {
                                    selectedRecordingID = recording.id
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(recording.name)
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundStyle(.white)
                                            Text(formattedDuration(recording.duration))
                                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                .foregroundStyle(.gray)
                                        }
                                        Spacer()
                                        if selectedRecordingID == recording.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .padding(.horizontal, 20)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
