import SwiftUI
import AlarmKit

struct ContentView: View {

    enum Mode { case alarms, timers }

    @State private var mode: Mode = .alarms
    @State private var showAddAlarm = false
    @State private var showAddTimer = false
    @State private var selectedTab: Int = 0
    @State private var groupToEdit: AlarmService.AlarmGroup? = nil

    @StateObject private var alarmService = AlarmService.shared
    @StateObject private var timerService = TimerService.shared

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false

    var quickActionMode: Binding<String?>

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                alarmsTimersTab
                    .tabItem { Label("Alarms", systemImage: "alarm") }
                    .tag(0)
                CalendarView()
                    .tabItem { Label("Calendar", systemImage: "calendar") }
                    .tag(1)
            }
            .tint(.orange)
            .onAppear {
                let appearance = UITabBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = UIColor(named: "AppBackground")
                UITabBar.appearance().standardAppearance = appearance
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }
            .onChange(of: quickActionMode.wrappedValue) {
                handleQuickAction()
            }

            if !hasSeenOnboarding {
                OnboardingView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: hasSeenOnboarding)
    }

    var alarmsTimersTab: some View {
        ZStack {
            Color("AppBackground").ignoresSafeArea()

            VStack(spacing: 0) {

                HStack {
                    Text(mode == .alarms ? "Alarms" : "Timers")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("PrimaryText"))
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

                HStack(spacing: 0) {
                    ForEach([Mode.alarms, Mode.timers], id: \.self) { m in
                        Button {
                            withAnimation(.spring(response: 0.3)) { mode = m }
                        } label: {
                            Text(m == .alarms ? "Alarms" : "Timers")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(mode == m ? .black : Color("SecondaryText"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(mode == m ? .orange : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(4)
                .background(Color("CardBackground"))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                List {
                    if mode == .alarms {
                        if alarmService.alarmGroups.isEmpty {
                            emptyState(icon: "alarm", text: "No alarms yet")
                                .listRowBackground(Color("AppBackground"))
                                .listRowSeparator(.hidden)
                        } else {
                            // ✅ Show 1 row per group
                            ForEach(alarmService.alarmGroups) { group in
                                AlarmGroupRow(group: group) {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    // Toggle all alarms in group
                                    for alarmID in group.alarmIDs {
                                        alarmService.toggleAlarm(id: alarmID)
                                    }
                                    alarmService.rebuildGroups()
                                }
                                .listRowBackground(Color("AppBackground"))
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                                .onTapGesture {
                                    groupToEdit = group
                                }
                                .swipeActions(edge: .leading) {}
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                        // ✅ Delete all alarms in group
                                        if let firstID = group.alarmIDs.first {
                                            alarmService.cancelAlarm(id: firstID)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        groupToEdit = group
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.orange)
                                }
                                .contextMenu {
                                    Button {
                                        groupToEdit = group
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                        if let firstID = group.alarmIDs.first {
                                            alarmService.cancelAlarm(id: firstID)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    } else {
                        if timerService.timers.isEmpty {
                            emptyState(icon: "timer", text: "No timers yet")
                                .listRowBackground(Color("AppBackground"))
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(timerService.timers) { timer in
                                TimerRow(timer: timer)
                                    .listRowBackground(Color("AppBackground"))
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                                    .swipeActions(edge: .leading) {}
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                            timerService.cancelTimer(id: timer.id)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                            timerService.cancelTimer(id: timer.id)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .background(Color("AppBackground"))
                .scrollContentBackground(.hidden)
            }
        }
        .sheet(isPresented: $showAddAlarm, onDismiss: {
            alarmService.loadAlarms()
        }) {
            AddAlarmView { date, title, snoozeEnabled, snoozeDuration, sound, repeatDays in
                Task {
                    _ = await alarmService.scheduleFutureAlarm(
                        date: date, title: title,
                        snoozeEnabled: snoozeEnabled,
                        snoozeDuration: snoozeDuration,
                        sound: sound,
                        repeatDays: repeatDays
                    )
                    await MainActor.run { alarmService.loadAlarms() }
                }
            }
        }
        // ✅ Edit group sheet
        .sheet(item: $groupToEdit, onDismiss: {
            alarmService.loadAlarms()
        }) { group in
            AddAlarmView(
                editingItem: alarmService.alarms.first(where: { group.alarmIDs.contains($0.id) }),
                repeatDaysToLoad: group.repeatDays
            ) { date, title, snoozeEnabled, snoozeDuration, sound, repeatDays in
                Task {
                    // Cancel all alarms in old group
                    if let firstID = group.alarmIDs.first {
                        alarmService.cancelAlarm(id: firstID)
                    }
                    // Schedule new
                    _ = await alarmService.scheduleFutureAlarm(
                        date: date, title: title,
                        snoozeEnabled: snoozeEnabled,
                        snoozeDuration: snoozeDuration,
                        sound: sound,
                        repeatDays: repeatDays
                    )
                    await MainActor.run { alarmService.loadAlarms() }
                }
            }
        }
        .sheet(isPresented: $showAddTimer, onDismiss: {
            timerService.loadTimers()
        }) {
            AddTimerView { duration, title, sound in
                Task {
                    await timerService.startTimer(duration: duration, title: title, sound: sound)
                    await MainActor.run { timerService.loadTimers() }
                }
            }
        }
        .onAppear {
            alarmService.loadAlarms()
            timerService.loadTimers()
        }
    }

    func handleQuickAction() {
        guard let action = quickActionMode.wrappedValue else { return }
        quickActionMode.wrappedValue = nil
        switch action {
        case "newAlarm":
            selectedTab = 0; mode = .alarms; showAddAlarm = true
        case "newTimer":
            selectedTab = 0; mode = .timers; showAddTimer = true
        case "fiveMinTimer":
            Task {
                await timerService.startTimer(duration: 300, title: "5 Min Timer", sound: "nokia.caf")
                await MainActor.run { timerService.loadTimers(); selectedTab = 0; mode = .timers }
            }
        case "settings":
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        default: break
        }
    }

    @ViewBuilder
    func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.orange.opacity(0.4))
            Text(text)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Color("SecondaryText"))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

// MARK: - Alarm Group Row (1 row per recurring group)
struct AlarmGroupRow: View {
    let group: AlarmService.AlarmGroup
    let onToggle: () -> Void

    private var subtitleText: String {
        let timeStr = group.fireDate.flatMap { date -> String? in
            let f = DateFormatter()
            f.dateFormat = "EEE, MMM d • h:mm a"
            return f.string(from: date)
        } ?? ""

        if group.repeatLabel.isEmpty {
            return timeStr
        } else {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            let timeOnly = group.fireDate.flatMap { f.string(from: $0) } ?? ""
            return "\(group.repeatLabel) • \(timeOnly)"
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(group.isEnabled ? .orange.opacity(0.15) : .gray.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: group.repeatDays.isEmpty ? "alarm" : "repeat")
                    .foregroundStyle(group.isEnabled ? .orange : .gray)
                    .font(.system(size: 20))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(group.label)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(group.isEnabled ? Color("PrimaryText") : Color("SecondaryText"))
                Text(subtitleText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color("SecondaryText"))
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { group.isEnabled },
                set: { _ in onToggle() }
            ))
            .tint(.orange)
            .labelsHidden()
        }
        .padding(16)
        .background(Color("CardBackground"))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .opacity(group.isEnabled ? 1.0 : 0.6)
    }
}

// MARK: - Timer Row
struct TimerRow: View {
    let timer: Alarm

    private var durationText: String {
        guard let duration = timer.countdownDuration else { return "Timer" }
        let total = Int(duration.preAlert ?? duration.postAlert ?? 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        else if hours > 0 { return "\(hours) hr" }
        else if minutes > 0 && seconds > 0 { return "\(minutes)m \(seconds)s" }
        else if minutes > 0 { return "\(minutes) min" }
        else { return "\(seconds) sec" }
    }

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
                Text(durationText)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color("PrimaryText"))
                Text("Timer")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color("SecondaryText"))
            }
            Spacer()
        }
        .padding(16)
        .background(Color("CardBackground"))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}


