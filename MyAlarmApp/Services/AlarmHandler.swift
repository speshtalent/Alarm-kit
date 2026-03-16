import Foundation
import AVFoundation

@MainActor
final class AlarmHandler {
    static let shared = AlarmHandler()
    private var audioPlayer: AVAudioPlayer?

    private init() {}

    // ✅ UPDATED — returns voice URL for a specific alarm ID
    private func voiceURL(for alarmID: String) -> URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let soundsURL = libraryURL.appendingPathComponent("Sounds")
        try? FileManager.default.createDirectory(at: soundsURL, withIntermediateDirectories: true)
        return soundsURL.appendingPathComponent("alarm_voice_\(alarmID).caf")
    }

    // ✅ UPDATED — plays voice for the specific alarm that just fired
    func playVoiceIfNeeded() {
        UserDefaults.standard.set(true, forKey: "alarmFiredSinceLastReview")
        print("⭐ Alarm fired — will ask for review on next app open")

        // ✅ ADDED — get which alarm fired
        let alarmID = UserDefaults.standard.string(forKey: "lastFiredAlarmID") ?? ""
        let url = voiceURL(for: alarmID)

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("No voice recording found for alarm: \(alarmID)")
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = 1.0
            audioPlayer?.play()
            print("🎙️ Playing voice for alarm: \(alarmID)")
        } catch {
            print("❌ Failed to play voice recording:", error)
        }
    }
}
