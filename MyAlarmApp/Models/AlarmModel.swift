import Foundation

/// Local model for displaying alarms in UI
/// This is NOT AlarmKit yet
struct AlarmModel: Identifiable, Hashable {
    let id: UUID
    var time: Date
    var title: String
    var isEnabled: Bool
}
