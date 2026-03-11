
import UIKit

class SceneDelegate: NSObject, UIWindowSceneDelegate {

    // this is called when app is in BACKGROUND and quick action tapped
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        print("🚀 SceneDelegate: \(shortcutItem.type)")
        NotificationCenter.default.post(
            name: NSNotification.Name("QuickActionTriggered"),
            object: shortcutItem.type
        )
        completionHandler(true)
    }
}
