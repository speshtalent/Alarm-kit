import Foundation

enum AlarmSoundChoice: Codable, Equatable {
    case systemDefault
    case customRecording(UUID)
}
