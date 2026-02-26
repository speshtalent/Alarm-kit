import AlarmKit

@MainActor
struct AlarmPermission {

    static func request() async {
        do {
            let status = try await AlarmManager.shared.requestAuthorization()
            print("AlarmKit authorization status:", status)
        } catch {
            print("AlarmKit permission error:", error)
        }
    }
}
