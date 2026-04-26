import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

struct SnoozeLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SnoozeLiveActivityAttributes.self) { context in
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "alarm.fill")
                            .foregroundStyle(.orange)
                        Text("Snoozed")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }

                    Text(context.state.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(context.state.endDate, style: .timer)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                }

                Spacer(minLength: 12)

                Button(intent: StopAlarmIntent(alarmID: context.attributes.alarmID)) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white)
                        .font(.system(size: 18, weight: .bold))
                        .padding(10)
                        .background(.gray.opacity(0.3), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.endDate, style: .timer)
                        .font(.caption.bold().monospaced())
                    .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 16) {
                        Text("Snoozed")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Button(intent: StopAlarmIntent(alarmID: context.attributes.alarmID)) {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                    }
                        .foregroundStyle(.orange)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                Text(context.state.endDate, style: .timer)
                    .font(.caption.bold().monospaced())
                    .foregroundStyle(.orange)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
            }
            .keylineTint(.orange)
        }
    }
}
