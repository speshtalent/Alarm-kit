import SwiftUI
import AlarmKit

struct ContentView: View {

    enum Mode { case alarms, timers }

    @State private var mode: Mode = .alarms
    @State private var showAddAlarm = false
    @State private var showAddTimer = false
    @State private var showSettings = false
    @State private var selectedTab: Int = 0
    @State private var groupToEdit: AlarmService.AlarmGroup? = nil
    @State private var pendingIntentAlarmDraft: PendingSetAlarmIntentDraft? = nil

    @StateObject private var alarmService = AlarmService.shared
    @StateObject private var timerService = TimerService.shared

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @AppStorage("appColorScheme") private var appColorScheme: String = "system"
    @AppStorage("use24HourFormat") private var use24HourFormat: Bool = false

    var quickActionMode: Binding<String?>

    private var preferredColorScheme: ColorScheme? {
        switch appColorScheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                alarmsTimersTab
                    .tabItem { Label("Alarms", systemImage: "alarm") }
                    .tag(0)
                CalendarView()
                    .tabItem { Label("Calendar", systemImage: "calendar") }
                    .tag(1)
                HistoryView()
                    .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                    .tag(2)
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
        .preferredColorScheme(preferredColorScheme)
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
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color("SecondaryText"))
                            .frame(width: 36, height: 36)
                            .background(Color("CardBackground"))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 8)

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
                            ForEach(alarmService.alarmGroups) { group in
                                AlarmGroupRow(group: group, use24Hour: use24HourFormat) {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        .sheet(isPresented: $showSettings) {
            SettingsView(preferredColorScheme: preferredColorScheme)
                .id(appColorScheme)
        }
        .sheet(isPresented: $showAddAlarm, onDismiss: {
            pendingIntentAlarmDraft = nil
            alarmService.loadAlarms()
        }) {
            AddAlarmView(
                preselectedDate: pendingIntentAlarmDraft?.date,
                initialTitle: pendingIntentAlarmDraft?.label,
                autoStartRecording: pendingIntentAlarmDraft?.shouldRecordVoice == true,
                repeatDaysToLoad: pendingIntentAlarmDraft?.repeatDays ?? []
            ) { date, title, snoozeEnabled, snoozeDuration, sound, repeatDays in
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
        .sheet(item: $groupToEdit, onDismiss: {
            alarmService.loadAlarms()
        }) { group in
            AddAlarmView(
                editingItem: alarmService.alarms.first(where: { group.alarmIDs.contains($0.id) }),
                repeatDaysToLoad: group.repeatDays
            ) { date, title, snoozeEnabled, snoozeDuration, sound, repeatDays in
                Task {
                    if let firstID = group.alarmIDs.first {
                        alarmService.cancelAlarm(id: firstID)
                    }
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
            consumePendingIntentAlarmFlowIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            consumePendingIntentAlarmFlowIfNeeded()
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
            showSettings = true
        default: break
        }
    }

    func consumePendingIntentAlarmFlowIfNeeded() {
        guard let draft = PendingSetAlarmIntentStore.consume() else { return }
        pendingIntentAlarmDraft = draft
        groupToEdit = nil
        selectedTab = 0
        mode = .alarms
        showAddTimer = false
        showAddAlarm = true
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

// MARK: - Settings View
struct SettingsView: View {
    @AppStorage("appColorScheme") private var appColorScheme: String = "system"
    @AppStorage("use24HourFormat") private var use24HourFormat: Bool = false
    @AppStorage("selectedAppIcon") private var selectedAppIcon: String = "Classic"
    @State private var pendingIcon: String = "Classic"
    @State private var showFeatureRequest = false
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.dismiss) private var dismiss

    var preferredColorScheme: ColorScheme?

    private let appIcons: [(name: String, imageName: String, iconName: String?)] = [
        ("Storm", "AppIcon6", "AppIcon6"),
        ("Blaze", "AppIcon7", "AppIcon7"),
        ("Classic", "AppIcon", nil),
        ("Future", "AppIcon2", "AppIcon2"),
        ("Pro", "AppIcon3", "AppIcon3"),
        ("Elite", "AppIcon4", "AppIcon4"),
        ("Neon", "AppIcon5", "AppIcon5"),
    ]

    private var useSystemDefault: Binding<Bool> {
        Binding(
            get: { appColorScheme == "system" },
            set: { newValue in
                if newValue {
                    UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .flatMap { $0.windows }
                        .forEach { $0.overrideUserInterfaceStyle = .unspecified }
                    appColorScheme = "system"
                    dismiss()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appColorScheme = effectiveScheme == .dark ? "dark" : "light"
                    }
                }
            }
        )
    }

    private var effectiveScheme: ColorScheme {
        switch appColorScheme {
        case "light": return .light
        case "dark": return .dark
        default: return systemColorScheme
        }
    }

    private var bgColor: Color {
        effectiveScheme == .dark
            ? Color(UIColor(red: 0.071, green: 0.071, blue: 0.078, alpha: 1))
            : Color(UIColor.systemGroupedBackground)
    }

    private var cardColor: Color {
        effectiveScheme == .dark
            ? Color(UIColor(red: 0.13, green: 0.13, blue: 0.14, alpha: 1))
            : Color(UIColor.secondarySystemGroupedBackground)
    }

    private var primaryText: Color {
        effectiveScheme == .dark ? .white : Color(UIColor.label)
    }

    private var secondaryText: Color {
        effectiveScheme == .dark ? Color(white: 0.55) : Color(UIColor.secondaryLabel)
    }

    private var currentColorScheme: ColorScheme? {
        switch appColorScheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {

                    RoundedRectangle(cornerRadius: 3)
                        .fill(secondaryText.opacity(0.4))
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)

                    Text("Settings")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(primaryText)
                        .padding(.bottom, 4)

                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(cardColor)
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Image(systemName: "circle.lefthalf.filled")
                                    .foregroundStyle(.orange)
                                Text("Appearance")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(primaryText)
                                Spacer()
                            }
                            .padding(16)
                            Divider()

                            HStack {
                                Text("System Default")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(primaryText)
                                Spacer()
                                Toggle("", isOn: useSystemDefault)
                                    .tint(.orange)
                            }
                            .padding(16)

                            if appColorScheme != "system" {
                                Divider()
                                appearanceRow(title: "Light Mode", value: "light")
                                Divider()
                                appearanceRow(title: "Dark Mode", value: "dark")
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(cardColor)
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Image(systemName: "app.fill")
                                    .foregroundStyle(.orange)
                                Text("App Icon")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(primaryText)
                                Spacer()
                            }
                            .padding(16)
                            Divider()

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(appIcons, id: \.name) { icon in
                                        VStack(spacing: 8) {
                                            Group {
                                                if let uiImage = UIImage(named: icon.imageName) {
                                                    Image(uiImage: uiImage)
                                                        .resizable()
                                                        .scaledToFit()
                                                } else {
                                                    RoundedRectangle(cornerRadius: 14)
                                                        .fill(Color.orange.opacity(0.2))
                                                }
                                            }
                                            .frame(width: 64, height: 64)
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14)
                                                    .stroke(pendingIcon == icon.name ? Color.orange : Color.clear, lineWidth: 3)
                                            )
                                            .shadow(color: pendingIcon == icon.name ? .orange.opacity(0.4) : .clear, radius: 6)

                                            Text(icon.name)
                                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                                .foregroundStyle(pendingIcon == icon.name ? .orange : secondaryText)

                                            if selectedAppIcon == icon.name {
                                                Text("Active")
                                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.3)) {
                                                pendingIcon = icon.name
                                            }
                                        }
                                    }
                                }
                                .padding(16)
                            }

                            if pendingIcon != selectedAppIcon {
                                Button {
                                    applyIcon()
                                } label: {
                                    Text("Apply")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(.black)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Color.orange)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                                .transition(.opacity)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .onAppear { pendingIcon = selectedAppIcon }

                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(cardColor)
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.fill")
                                    .foregroundStyle(.orange)
                                Text("Time Format")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(primaryText)
                                Spacer()
                            }
                            .padding(16)
                            Divider()
                            HStack {
                                Text("24 Hour")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(primaryText)
                                Spacer()
                                Toggle("", isOn: $use24HourFormat)
                                    .tint(.orange)
                                    .onChange(of: use24HourFormat) {
                                        AlarmService.shared.saveNextAlarmForWidget()
                                    }
                            }
                            .padding(16)
                        }
                    }
                    .padding(.horizontal, 20)

                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(cardColor)
                        HStack(spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(.orange)
                            Text("Request a Feature")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(primaryText)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(secondaryText)
                                .font(.system(size: 13))
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 20)
                    .onTapGesture { showFeatureRequest = true }

                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(cardColor)
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.orange)
                            Text("Version")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(primaryText)
                            Spacer()
                            Text(appVersion)
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(secondaryText)
                        }
                        .padding(16)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(currentColorScheme)
        .sheet(isPresented: $showFeatureRequest) {
            FeatureRequestView()
                .preferredColorScheme(currentColorScheme)
        }
    }

    private func applyIcon() {
        guard let icon = appIcons.first(where: { $0.name == pendingIcon }) else { return }
        UIApplication.shared.setAlternateIconName(icon.iconName) { error in
            if error == nil {
                DispatchQueue.main.async {
                    selectedAppIcon = pendingIcon
                }
            }
        }
    }

    @ViewBuilder
    private func appearanceRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(primaryText)
            Spacer()
            if appColorScheme == value {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                appColorScheme = value
            }
        }
    }
}

// MARK: - Feature Request View
struct FeatureRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var requestText = ""
    @State private var showNoMailAlert = false

    private let supportEmail = "robin@speshtalent.com"

    var body: some View {
        ZStack {
            Color("AppBackground").ignoresSafeArea()
            VStack(spacing: 20) {

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color("SecondaryText").opacity(0.4))
                    .frame(width: 40, height: 5)
                    .padding(.top, 12)

                Text("Request a Feature")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color("PrimaryText"))

                Text("Tell us what you'd like to see in Date Alarm!")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color("SecondaryText"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 16).fill(Color("CardBackground"))
                    if requestText.isEmpty {
                        Text("Describe your feature idea...")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(Color("SecondaryText").opacity(0.5))
                            .padding(16)
                    }
                    TextEditor(text: $requestText)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(Color("PrimaryText"))
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .padding(12)
                        .frame(height: 160)
                }
                .frame(height: 160)
                .padding(.horizontal, 20)

                Button {
                    sendFeatureRequest()
                } label: {
                    Text("Send Request")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(requestText.isEmpty ? Color.orange.opacity(0.4) : Color.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .disabled(requestText.isEmpty)
                .padding(.horizontal, 20)

                Spacer()
            }
        }
        .alert("Mail Not Set Up", isPresented: $showNoMailAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please set up the Mail app on your iPhone to send feature requests.")
        }
    }

    private func sendFeatureRequest() {
        let subject = "Feature Request — Date Alarm"
        let body = requestText
        let urlString = "mailto:\(supportEmail)?subject=\(subject)&body=\(body)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            showNoMailAlert = true
        }
    }
}

// MARK: - Alarm Group Row
struct AlarmGroupRow: View {
    let group: AlarmService.AlarmGroup
    let use24Hour: Bool
    let onToggle: () -> Void

    // ✅ Only this changed — added Monthly/Yearly support
    private var subtitleText: String {
        let f = DateFormatter()
        f.dateFormat = use24Hour ? "EEE, MMM d • HH:mm" : "EEE, MMM d • h:mm a"
        let tf = DateFormatter()
        tf.dateFormat = use24Hour ? "HH:mm" : "h:mm a"
        let timeOnly = group.fireDate.flatMap { tf.string(from: $0) } ?? ""

        if group.repeatDays == Set([100]) { return "Monthly • \(timeOnly)" }
        if group.repeatDays == Set([200]) { return "Yearly • \(timeOnly)" }
        if group.repeatLabel.isEmpty {
            return group.fireDate.flatMap { f.string(from: $0) } ?? ""
        } else {
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

// MARK: - History View
struct HistoryView: View {
    @AppStorage("use24HourFormat") private var use24HourFormat: Bool = false
    @State private var history: [[String: Any]] = []
    @State private var showClearAlert = false

    var body: some View {
        ZStack {
            Color("AppBackground").ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("History")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("PrimaryText"))
                    Spacer()
                    if !history.isEmpty {
                        Button {
                            showClearAlert = true
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color("SecondaryText"))
                                .frame(width: 36, height: 36)
                                .background(Color("CardBackground"))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)

                if history.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange.opacity(0.4))
                        Text("No alarm history yet")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(Color("SecondaryText"))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 80)
                } else {
                    List {
                        ForEach(Array(history.enumerated()), id: \.offset) { _, entry in
                            let label = entry["label"] as? String ?? "Alarm"
                            let firedAt = entry["firedAt"] as? TimeInterval ?? 0
                            let date = Date(timeIntervalSince1970: firedAt)
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(.orange.opacity(0.15))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.system(size: 20))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(label)
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color("PrimaryText"))
                                    Text(formatDate(date))
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color("SecondaryText"))
                                }
                                Spacer()
                            }
                            .padding(16)
                            .background(Color("CardBackground"))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .listRowBackground(Color("AppBackground"))
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                        }
                    }
                    .listStyle(.plain)
                    .background(Color("AppBackground"))
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .onAppear {
            history = AlarmService.shared.loadHistory()
        }
        .alert("Clear History", isPresented: $showClearAlert) {
            Button("Clear", role: .destructive) {
                AlarmService.shared.clearHistory()
                history = []
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to clear all alarm history?")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = use24HourFormat ? "EEE, MMM d • HH:mm" : "EEE, MMM d • h:mm a"
        return f.string(from: date)
    }
}
