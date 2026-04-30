import WidgetKit
import SwiftUI
import AlarmKit
import AppIntents

struct CountdownLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<AlarmLiveActivityMetadata>.self) { context in
            let metadata = context.attributes.metadata
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "alarm.fill")
                            .foregroundStyle(.orange)
                        Text("Alarm")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }

                    Text(metadata?.title ?? "Alarm")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    alarmStatusText(state: context.state)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Button(intent: RepeatAlarmIntent(alarmID: context.state.alarmID.uuidString)) {
                        Image(systemName: "moon.zzz.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 18, weight: .bold))
                            .padding(10)
                            .background(.orange.opacity(0.25), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button(intent: StopAlarmIntent(alarmID: context.state.alarmID.uuidString)) {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white)
                            .font(.system(size: 18, weight: .bold))
                            .padding(10)
                            .background(.gray.opacity(0.3), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(.black)
        } dynamicIsland: { context in
            let metadata = context.attributes.metadata
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(metadata?.title ?? "Alarm")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    alarmCompactText(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 16) {
                        alarmStatusText(state: context.state)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Button(intent: StopAlarmIntent(alarmID: context.state.alarmID.uuidString)) {
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
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
            }
            .keylineTint(.orange)
        }
    }

    @ViewBuilder
    private func alarmStatusText(state: AlarmPresentationState) -> some View {
        switch state.mode {
        case .countdown(let countdown):
            VStack(alignment: .leading, spacing: 2) {
                Text("Snoozed")
                    .font(.caption.weight(.semibold))
                // WHY: AlarmKit supplies the snooze fire date in countdown mode, so the
                // system timer stays live without app-side refreshes or a second activity.
                Text(countdown.fireDate, style: .timer)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(.orange)
        default:
            Text("Alarm Active")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func alarmCompactText(state: AlarmPresentationState) -> some View {
        switch state.mode {
        case .countdown(let countdown):
            Text(countdown.fireDate, style: .timer)
                .font(.caption.bold().monospaced())
                .foregroundStyle(.orange)
        default:
            Button(intent: StopAlarmIntent(alarmID: state.alarmID.uuidString)) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.orange)
        }
    }
}
