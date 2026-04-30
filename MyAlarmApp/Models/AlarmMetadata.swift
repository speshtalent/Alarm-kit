import Foundation
import AlarmKit
import ActivityKit

nonisolated struct AlarmLiveActivityMetadata: AlarmMetadata {
    var title: String
    var icon: String
}

nonisolated struct TimerAlarmMetadata: AlarmMetadata {
    var title: String
    var icon: String
}

nonisolated struct TimerLiveActivityMetadata: AlarmMetadata {
    var title: String
    var icon: String
}

struct SnoozeLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var endDate: Date
    }

    let alarmID: String
}

enum LiveActivityCoordinator {
    static func endAllActivities() async {
        await endAlarmActivities()
        await endTimerActivities()
        await endSnoozeActivity()
    }

    static func endAlarmActivities() async {
        await endActivities(for: Activity<AlarmAttributes<AlarmLiveActivityMetadata>>.activities)
    }

    static func endTimerActivities() async {
        await endActivities(for: Activity<AlarmAttributes<TimerAlarmMetadata>>.activities)
        await endActivities(for: Activity<AlarmAttributes<TimerLiveActivityMetadata>>.activities)
    }

    static func startSnoozeActivity(alarmID: String, title: String, endDate: Date) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let snoozeDate = max(endDate, Date().addingTimeInterval(1))
        let content = ActivityContent(
            state: SnoozeLiveActivityAttributes.ContentState(
                title: "Snoozed",
                endDate: snoozeDate
            ),
            staleDate: snoozeDate
        )

        var matchingActivity: Activity<SnoozeLiveActivityAttributes>?
        for activity in Activity<SnoozeLiveActivityAttributes>.activities {
            if activity.attributes.alarmID == alarmID, matchingActivity == nil {
                matchingActivity = activity
            } else {
                // WHY: the snooze affordance must map to one visible countdown, and stale
                // activities can keep rendering old alarm IDs/actions after the alarm was rescheduled.
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        if let matchingActivity {
            // WHY: repeated snooze taps should move the countdown forward without dismissing
            // the current Lock Screen/Dynamic Island presentation.
            await matchingActivity.update(content)
            return
        }

        let attributes = SnoozeLiveActivityAttributes(alarmID: alarmID)
        do {
            // WHY: AlarmKit may have already torn down the ringing activity before this intent
            // runs, so snooze must be able to create the replacement countdown from zero.
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            print("❌ Failed to start snooze live activity:", error)
        }
    }

    static func endSnoozeActivity(alarmID: String? = nil) async {
        let activities = Activity<SnoozeLiveActivityAttributes>.activities.filter { activity in
            guard let alarmID else { return true }
            return activity.attributes.alarmID == alarmID
        }
        await endActivities(for: activities)
    }

    static func syncSnoozeActivities(
        activeSnoozes: [String: Date],
        labels: [String: String]
    ) async {
        let now = Date()
        let normalized = activeSnoozes.filter { $0.value > now }

        for activity in Activity<SnoozeLiveActivityAttributes>.activities {
            let alarmID = activity.attributes.alarmID
            guard let endDate = normalized[alarmID] else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }

            let content = ActivityContent(
                state: SnoozeLiveActivityAttributes.ContentState(
                    title: labels[alarmID] ?? "Alarm",
                    endDate: endDate
                ),
                staleDate: endDate
            )
            await activity.update(content)
        }
    }

    private static func endActivities<Attributes: ActivityAttributes>(
        for activities: [Activity<Attributes>]
    ) async {
        // WHY: AlarmKit can keep rendering the most recent matching activity unless the old
        // instance is closed, which is what caused stale icon/title reuse between alarm and timer.
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
