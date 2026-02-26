import WidgetKit
import SwiftUI
import AlarmKit
import AppIntents

struct CountdownLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<AppAlarmMetadata>.self) { context in

            // ---- LOCK SCREEN UI ----
            HStack(spacing: 16) {

                HStack(spacing: 8) {
                    Button(intent: RepeatAlarmIntent(alarmID: context.state.alarmID.uuidString)) {
                        Image(systemName: "repeat")
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

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: context.attributes.metadata?.icon ?? "timer")
                        .foregroundStyle(.orange)
                    Text(context.attributes.metadata?.title ?? "Timer")
                        .foregroundStyle(.white)

                    countdownText(state: context.state)
                        .foregroundStyle(.orange)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(.black)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.metadata?.icon ?? "timer")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdownText(state: context.state)
                        .foregroundStyle(.orange)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    EmptyView()
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                countdownText(state: context.state)
                    .foregroundStyle(.orange)
                    .font(.caption.bold().monospaced())
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func countdownText(state: AlarmPresentationState) -> some View {
        switch state.mode {
        case .countdown(let c):
            let remaining = c.totalCountdownDuration - c.previouslyElapsedDuration
            Text(timerInterval: c.startDate...c.startDate.addingTimeInterval(remaining), countsDown: true)
        case .paused(let p):
            let remaining = p.totalCountdownDuration - p.previouslyElapsedDuration
            Text(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))
        default:
            Text("0:00")
        }
    }
}
