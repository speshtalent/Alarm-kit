import Foundation
import AVFoundation

@MainActor
final class AlarmHandler {
    static let shared = AlarmHandler()
    private var audioPlayer: AVAudioPlayer?

    private init() {}

    private var recordingURL: URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let soundsURL = libraryURL.appendingPathComponent("Sounds")
        try? FileManager.default.createDirectory(at: soundsURL, withIntermediateDirectories: true)
        return soundsURL.appendingPathComponent("alarm_voice.caf")
    }

    func playVoiceIfNeeded() {
        guard FileManager.default.fileExists(atPath: recordingURL.path) else {
            print("No voice recording found")
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try AVAudioPlayer(contentsOf: recordingURL)
            audioPlayer?.volume = 1.0
            audioPlayer?.play()
            print("🎙️ Playing voice recording!")
        } catch {
            print("❌ Failed to play voice recording:", error)
        }
    }
}
