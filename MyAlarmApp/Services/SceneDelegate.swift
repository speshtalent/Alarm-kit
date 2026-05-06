
import UIKit

class SceneDelegate: NSObject, UIWindowSceneDelegate {

    // this is called when app is in BACKGROUND and quick action tapped
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        print("🚀 SceneDelegate: \(shortcutItem.type)")
        if shortcutItem.type == "shareApp" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let scene = windowScene.windows.first else { return }
                let av = UIActivityViewController(
                    activityItems: ["Check out Date Alarm!", URL(string: "https://apps.apple.com/us/app/date-alarm/id6761073513")!],
                    applicationActivities: nil
                )
                scene.rootViewController?.present(av, animated: true)
            }
        } else {
            NotificationCenter.default.post(
                name: NSNotification.Name("QuickActionTriggered"),
                object: shortcutItem.type
            )
        }
        completionHandler(true)
    }
}
