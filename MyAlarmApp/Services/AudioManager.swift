import Foundation
import AVFoundation
import Combine

enum AudioManagerError: LocalizedError {
    case permissionDenied
    case noRecordingAvailable
    case failedToPrepare

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission was denied."
        case .noRecordingAvailable:
            return "The recording file could not be found."
        case .failedToPrepare:
            return "Unable to prepare audio session."
        }
    }
}

protocol AudioManaging: AnyObject {
    var isRecording: Bool { get }
    var isPlayingPreview: Bool { get }

    func requestMicrophonePermission() async -> Bool
    func startRecording(to url: URL) throws
    func stopRecording() -> TimeInterval
    func togglePreviewPlayback(url: URL) throws -> Bool
    func stopPreviewPlayback()
    func playAlarmLoop(url: URL, fadeIn: Bool) throws
    func stopAlarmLoop()
}

final class AudioManager: NSObject, ObservableObject, AudioManaging {
    static let shared = AudioManager()

    @Published private(set) var isRecording = false
    @Published private(set) var isPlayingPreview = false

    private var recorder: AVAudioRecorder?
    private var previewPlayer: AVAudioPlayer?
    private var alarmPlayer: AVAudioPlayer?
    private var fadeTimer: Timer?
    private var recordingStartDate: Date?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording(to url: URL) throws {
        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            throw AudioManagerError.permissionDenied
        }

        try configureSessionForRecord()

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.isMeteringEnabled = true
        guard recorder?.prepareToRecord() == true else {
            throw AudioManagerError.failedToPrepare
        }

        recorder?.record()
        recordingStartDate = Date()
        isRecording = true
    }

    func stopRecording() -> TimeInterval {
        recorder?.stop()
        let duration = recorder?.currentTime ?? Date().timeIntervalSince(recordingStartDate ?? Date())
        recorder = nil
        recordingStartDate = nil
        isRecording = false
        return max(0, duration)
    }

    func togglePreviewPlayback(url: URL) throws -> Bool {
        if isPlayingPreview {
            stopPreviewPlayback()
            return false
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioManagerError.noRecordingAvailable
        }

        try configureSessionForPlayback()
        previewPlayer = try AVAudioPlayer(contentsOf: url)
        previewPlayer?.delegate = self
        previewPlayer?.numberOfLoops = 0
        previewPlayer?.prepareToPlay()
        previewPlayer?.play()
        isPlayingPreview = true
        return true
    }

    func stopPreviewPlayback() {
        previewPlayer?.stop()
        previewPlayer = nil
        isPlayingPreview = false
    }

    func playAlarmLoop(url: URL, fadeIn: Bool) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioManagerError.noRecordingAvailable
        }

        try configureSessionForPlayback(duckOthers: false)

        if alarmPlayer?.url == url, alarmPlayer?.isPlaying == true {
            return
        }

        alarmPlayer?.stop()
        alarmPlayer = try AVAudioPlayer(contentsOf: url)
        alarmPlayer?.numberOfLoops = -1
        alarmPlayer?.delegate = self

        if fadeIn {
            alarmPlayer?.volume = 0
        } else {
            alarmPlayer?.volume = 1
        }

        alarmPlayer?.prepareToPlay()
        alarmPlayer?.play()

        if fadeIn {
            startFadeIn()
        }
    }

    func stopAlarmLoop() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        alarmPlayer?.stop()
        alarmPlayer = nil
    }

    @objc
    private func handleInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            previewPlayer?.pause()
            alarmPlayer?.pause()
        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                if isPlayingPreview {
                    previewPlayer?.play()
                }
                if alarmPlayer != nil {
                    alarmPlayer?.play()
                }
            }
        @unknown default:
            break
        }
    }

    private func configureSessionForRecord() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
    }

    private func configureSessionForPlayback(duckOthers: Bool = true) throws {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = [.mixWithOthers]
        if duckOthers {
            options.insert(.duckOthers)
        }
        try session.setCategory(.playback, mode: .default, options: options)
        try session.setActive(true)
    }

    private func startFadeIn() {
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            guard let player = self.alarmPlayer else {
                timer.invalidate()
                return
            }
            if player.volume >= 1 {
                player.volume = 1
                timer.invalidate()
                return
            }
            player.volume = min(1, player.volume + 0.1)
        }
    }
}

extension AudioManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if player === previewPlayer {
            isPlayingPreview = false
            previewPlayer = nil
        }
    }
}
