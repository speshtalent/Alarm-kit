import WidgetKit
import SwiftUI

@main
struct CountdownLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        CountdownLiveActivityWidget()
        TimerLiveActivityWidget()
        SnoozeLiveActivityWidget()
    }
}
