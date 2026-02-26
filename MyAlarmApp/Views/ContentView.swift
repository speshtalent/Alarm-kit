import SwiftUI
import AlarmKit

struct ContentView: View {

    enum Mode { case alarms, timers }

    @State private var mode: Mode = .alarms
    @State private var showAddAlarm = false
    @State private var showAddTimer = false

    @StateObject private var alarmService = AlarmService.shared
    @StateObject private var timerService = TimerService.shared

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.09)
                .ignoresSafeArea()

            VStack(spacing: 0) {

                // MARK: Header
                HStack {
                    Text(mode == .alarms ? "Alarms" : "Timers")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        mode == .alarms ? (showAddAlarm = true) : (showAddTimer = true)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 36, height: 36)
                            .background(.orange)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)


                // MARK: Segmented Picker
                HStack(spacing: 0) {
                    ForEach([Mode.alarms, Mode.timers], id: \.self) { m in
                        Button {
                            withAnimation(.spring(response: 0.3)) { mode = m }
                        } label: {
                            Text(m == .alarms ? "Alarms" : "Timers")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(mode == m ? .black : .gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(mode == m ? .orange : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(4)
                .background(Color(white: 0.15))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                // MARK: List
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if mode == .alarms {
                            if alarmService.alarms.isEmpty {
                                emptyState(icon: "alarm", text: "No alarms yet")
                            } else {
                                ForEach(alarmService.alarms) { alarm in
                                    AlarmRow(alarm: alarm) {
                                        alarmService.cancelAlarm(id: alarm.id)
                                    }
                                }
                            }
                        } else {
                            if timerService.timers.isEmpty {
                                emptyState(icon: "timer", text: "No timers yet")
                            } else {
                                ForEach(timerService.timers) { timer in
                                    TimerRow(timer: timer) {
                                        timerService.cancelTimer(id: timer.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .sheet(isPresented: $showAddAlarm, onDismiss: {
            alarmService.loadAlarms()
        }) {
            AddAlarmView { date, title, snoozeEnabled, snoozeDuration in
                Task {
                    await alarmService.scheduleFutureAlarm(
                        date: date,
                        title: title,
                        snoozeEnabled: snoozeEnabled,
                        snoozeDuration: snoozeDuration
                    )
                    await MainActor.run {
                        alarmService.loadAlarms()
                    }
                }
            }
        }
        .sheet(isPresented: $showAddTimer, onDismiss: {
            timerService.loadTimers()
        }) {
            AddTimerView { duration, title in
                Task {
                    await timerService.startTimer(
                        duration: duration,
                        title: title
                    )
                    await MainActor.run {
                        timerService.loadTimers()
                    }
                }
            }
        }
        .onAppear {
            alarmService.loadAlarms()
            timerService.loadTimers()
        }
    }

    @ViewBuilder
    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.orange.opacity(0.4))
            Text(text)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

// MARK: - Alarm Row
struct AlarmRow: View {
    let alarm: Alarm
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "alarm")
                    .foregroundStyle(.orange)
                    .font(.system(size: 20))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Alarm")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(alarm.id.uuidString.prefix(8).uppercased())
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.gray)
            }

            Spacer()

            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(.orange.opacity(0.6))
                .font(.system(size: 14))

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(8)
                    .background(.red.opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .padding(16)
        .background(Color(white: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Timer Row
struct TimerRow: View {
    let timer: Alarm
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "timer")
                    .foregroundStyle(.orange)
                    .font(.system(size: 20))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Timer")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(timer.id.uuidString.prefix(8).uppercased())
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.gray)
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(8)
                    .background(.red.opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .padding(16)
        .background(Color(white: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
