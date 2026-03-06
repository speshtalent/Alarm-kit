//
//  CountdownLiveActivityLiveActivity.swift
//  CountdownLiveActivity
//
//  Created by Maniraj on 2/26/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct CountdownLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct CountdownLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CountdownLiveActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension CountdownLiveActivityAttributes {
    fileprivate static var preview: CountdownLiveActivityAttributes {
        CountdownLiveActivityAttributes(name: "World")
    }
}

extension CountdownLiveActivityAttributes.ContentState {
    fileprivate static var smiley: CountdownLiveActivityAttributes.ContentState {
        CountdownLiveActivityAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: CountdownLiveActivityAttributes.ContentState {
         CountdownLiveActivityAttributes.ContentState(emoji: "🤩")
     }
}

// Preview macros are disabled to keep CLI builds stable in sandboxed environments.
