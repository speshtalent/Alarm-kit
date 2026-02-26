import SwiftUI

@main
struct MyAlarmAppApp: App {

    init() {
        Task {
            await AlarmPermission.request()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
