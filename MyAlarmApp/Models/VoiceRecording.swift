import Foundation
import CoreData

@objc(VoiceRecording)
public final class VoiceRecording: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<VoiceRecording> {
        NSFetchRequest<VoiceRecording>(entityName: "VoiceRecording")
    }

    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var duration: Double
    @NSManaged public var relativePath: String
    @NSManaged public var createdAt: Date
}

extension VoiceRecording {
    static func create(
        in context: NSManagedObjectContext,
        name: String,
        duration: TimeInterval,
        relativePath: String
    ) -> VoiceRecording {
        let recording = VoiceRecording(context: context)
        recording.id = UUID()
        recording.name = name
        recording.duration = duration
        recording.relativePath = relativePath
        recording.createdAt = Date()
        return recording
    }

    var fileURL: URL {
        VoiceRecordingStorage.recordingsDirectory.appendingPathComponent(relativePath)
    }
}

enum VoiceRecordingStorage {
    static var recordingsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = documents.appendingPathComponent("Recordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
