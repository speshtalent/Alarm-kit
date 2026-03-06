import SwiftUI
import CoreData

struct VoiceRecordingsView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: VoiceRecordingsViewModel
    @State private var permissionDenied = false

    init(context: NSManagedObjectContext) {
        _viewModel = StateObject(wrappedValue: VoiceRecordingsViewModel(context: context))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.07, green: 0.07, blue: 0.09).ignoresSafeArea()

                VStack(spacing: 14) {
                    recordingControl
                    recordingsList
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("Voice Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            let granted = await viewModel.requestPermission()
            permissionDenied = !granted
        }
        .alert("Microphone Access Required", isPresented: $permissionDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable microphone access in Settings to record custom alarm tones.")
        }
        .alert("Audio Error", isPresented: Binding(get: {
            viewModel.lastErrorMessage != nil
        }, set: { newValue in
            if !newValue { viewModel.lastErrorMessage = nil }
        })) {
            Button("OK", role: .cancel) {
                viewModel.lastErrorMessage = nil
            }
        } message: {
            Text(viewModel.lastErrorMessage ?? "")
        }
    }

    private var recordingControl: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Circle()
                    .fill(viewModel.isRecording ? Color.red : Color.orange)
                    .frame(width: 14, height: 14)
                    .scaleEffect(viewModel.isRecording ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: viewModel.isRecording)

                Text(timerText(viewModel.recordingElapsed))
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button(viewModel.isRecording ? "Stop" : "Record") {
                    viewModel.toggleRecording()
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(viewModel.isRecording ? Color.red : Color.orange)
                .foregroundStyle(.black)
                .clipShape(Capsule())
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let progress = min(1.0, max(0.02, viewModel.isRecording ? (viewModel.recordingElapsed.truncatingRemainder(dividingBy: 10) / 10) : 0.02))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.15))
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
                        .frame(width: width * progress)
                }
            }
            .frame(height: 12)
        }
        .padding(16)
        .background(Color(white: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var recordingsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Saved Recordings")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(viewModel.recordings.count)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
            }

            if viewModel.recordings.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange.opacity(0.6))
                    Text("No recordings yet")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(white: 0.11))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.recordings, id: \.id) { recording in
                            recordingRow(recording)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .background(Color(white: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func recordingRow(_ recording: VoiceRecording) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    viewModel.togglePlayback(for: recording)
                } label: {
                    Image(systemName: viewModel.isPlayingID == recording.id ? "stop.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)

                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(timerText(recording.duration))")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.gray)
                }

                Spacer()

                Button {
                    viewModel.startRename(recording: recording)
                } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.borderless)

                Button(role: .destructive) {
                    viewModel.delete(recording: recording)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.9))
                }
                .buttonStyle(.borderless)
            }

            if viewModel.showingRenameForID == recording.id {
                HStack(spacing: 8) {
                    TextField("Recording name", text: $viewModel.renameText)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        viewModel.commitRename(for: recording)
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button("Cancel") {
                        viewModel.cancelRename()
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.gray)
                }
            }
        }
        .padding(12)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func timerText(_ time: TimeInterval) -> String {
        let total = Int(time.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
