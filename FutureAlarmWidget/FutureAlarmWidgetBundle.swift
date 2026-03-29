import WidgetKit
import SwiftUI

@main
struct FutureAlarmWidgetBundle: WidgetBundle {
    var body: some Widget {
        FutureAlarmWidget()
        CountdownWidget()
        TimeOnlyWidget()
        LockScreenWidget()  // ✅ NEW — lock screen widget
    }
}
