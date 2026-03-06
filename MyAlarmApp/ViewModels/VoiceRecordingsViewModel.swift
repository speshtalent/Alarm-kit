import Foundation
import CoreData
import Combine

@MainActor
final class VoiceRecordingsViewModel: ObservableObject {
    @Published private(set) var recordings: [VoiceRecording] = []
    @Published var isRecording = false
    @Published var isPlayingID: UUID?
    @Published var recordingElapsed: TimeInterval = 0
    @Published var lastErrorMessage: String?
    @Published var showingRenameForID: UUID?
    @Published var renameText: String = ""

    private let context: NSManagedObjectContext
    private let audioManager: AudioManaging
    private var recordingTimer: Timer?
    private var tempRecordingURL: URL?

    init(context: NSManagedObjectContext) {
        self.context = context
        self.audioManager = AudioManager.shared
        refreshRecordings()
    }

    init(context: NSManagedObjectContext, audioManager: AudioManaging) {
        self.context = context
        self.audioManager = audioManager
        refreshRecordings()
    }

    func refreshRecordings() {
        let request = VoiceRecording.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(VoiceRecording.createdAt), ascending: false)]
        recordings = (try? context.fetch(request)) ?? []
    }

    func requestPermission() async -> Bool {
        await audioManager.requestMicrophonePermission()
    }

    func toggleRecording() {
        if isRecording {
            finishRecordingAndSave()
        } else {
            beginRecording()
        }
    }

    func togglePlayback(for recording: VoiceRecording) {
        if isPlayingID == recording.id {
            audioManager.stopPreviewPlayback()
            isPlayingID = nil
            return
        }

        do {
            let didStart = try audioManager.togglePreviewPlayback(url: recording.fileURL)
            isPlayingID = didStart ? recording.id : nil
        } catch {
            isPlayingID = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    func delete(recording: VoiceRecording) {
        if isPlayingID == recording.id {
            audioManager.stopPreviewPlayback()
            isPlayingID = nil
        }

        let url = recording.fileURL
        context.delete(recording)
        do {
            try context.save()
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            refreshRecordings()
        } catch {
            context.rollback()
            lastErrorMessage = "Failed to delete recording."
        }
    }

    func startRename(recording: VoiceRecording) {
        showingRenameForID = recording.id
        renameText = recording.name
    }

    func commitRename(for recording: VoiceRecording) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showingRenameForID = nil
            return
        }

        recording.name = trimmed
        do {
            try context.save()
            refreshRecordings()
        } catch {
            context.rollback()
            lastErrorMessage = "Unable to rename recording."
        }
        showingRenameForID = nil
    }

    func cancelRename() {
        showingRenameForID = nil
        renameText = ""
    }

    private func beginRecording() {
        let fileName = "voice-\(UUID().uuidString).m4a"
        let url = VoiceRecordingStorage.recordingsDirectory.appendingPathComponent(fileName)

        do {
            try audioManager.startRecording(to: url)
            tempRecordingURL = url
            isRecording = true
            recordingElapsed = 0
            startTimer()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func finishRecordingAndSave() {
        let duration = audioManager.stopRecording()
        stopTimer()
        isRecording = false

        guard let tempRecordingURL else {
            return
        }
        defer { self.tempRecordingURL = nil }

        let minimumDuration: TimeInterval = 0.2
        guard duration >= minimumDuration else {
            try? FileManager.default.removeItem(at: tempRecordingURL)
            return
        }

        let fallbackName = "Recording \(Date.now.formatted(date: .abbreviated, time: .shortened))"
        let recording = VoiceRecording.create(
            in: context,
            name: fallbackName,
            duration: duration,
            relativePath: tempRecordingURL.lastPathComponent
        )

        do {
            try context.save()
            refreshRecordings()
            startRename(recording: recording)
        } catch {
            context.rollback()
            lastErrorMessage = "Failed to save recording."
        }
    }

    private func startTimer() {
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.recordingElapsed += 0.25
            }
        }
    }

    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
}
