import WidgetKit
import SwiftUI

@main
struct FutureAlarmWidgetBundle: WidgetBundle {
    var body: some Widget {
        FutureAlarmWidget()
        LockScreenWidget()
    }
}
