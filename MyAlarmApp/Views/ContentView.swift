import SwiftUI
import UIKit
import AlarmKit
import CoreSpotlight

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAddAlarm = false
    @State private var showSettings = false
    @State private var selectedTab: Int = 0
    @State private var groupToEdit: AlarmService.AlarmGroup? = nil
    @State private var showAlarmPermissionAlert = false
    @State private var showMicPermissionAlert = false
    @State private var showCalendarPermissionAlert = false
    @State private var pendingIntentAlarmDraft: PendingSetAlarmIntentDraft? = nil
    
    @StateObject private var alarmService = AlarmService.shared
    
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
        rootChrome
    }

    /// Split from `body` so the compiler can type-check the tab shell without growing the main `body` expression.
    private var rootChrome: some View {
        mainTabInterface
            .animation(.easeInOut(duration: 0.4), value: hasSeenOnboarding)
            .preferredColorScheme(preferredColorScheme)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                alarmService.loadAlarms()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    alarmService.loadAlarms()
                }
            }
    }

    @ViewBuilder
    private var mainTabInterface: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                alarmsTab
                    .tabItem { Label("Alarms", systemImage: "alarm") }
                    .tag(0)
                CalendarView()
                    .tabItem { Label("Calendar", systemImage: "calendar") }
                    .tag(1)
                ScheduledView()
                    .tabItem { Label("Scheduled", systemImage: "list.bullet.clipboard")}
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
    }

    @ViewBuilder
    private var alarmsTabMainContent: some View {
        ZStack {
            Color("AppBackground").ignoresSafeArea()

            VStack(spacing: 0) {

                HStack {
                    Text("Alarms")
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
                        Task {
                            await AlarmService.shared.requestAuthorizationIfNeeded()
                            await MainActor.run {
                                if AlarmManager.shared.authorizationState == .denied {
                                    showAlarmPermissionAlert = true
                                } else {
                                    showAddAlarm = true
                                }
                            }
                        }
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
                .padding(.bottom, 20)

                List {
                    if alarmService.alarmGroups.isEmpty {
                        emptyState(icon: "alarm", text: "No alarms yet")
                            .listRowBackground(Color("AppBackground"))
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(alarmService.alarmGroups) { group in
                            AlarmGroupRow(group: group) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                for alarmID in group.alarmIDs {
                                    alarmService.toggleAlarm(id: alarmID)
                                }
                                Task {
                                    try? await Task.sleep(nanoseconds: 300_000_000)
                                    await MainActor.run {
                                        alarmService.loadAlarms()
                                    }
                                }
                            }
                            .listRowBackground(Color("AppBackground"))
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                            .onTapGesture {
                                if group.isFired {
                                    AlarmService.shared.removeFiredAlarm(alarmID: group.id.uuidString)
                                    AlarmService.shared.loadAlarms()
                                    groupToEdit = group
                                } else {
                                    groupToEdit = group
                                }
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
                }
                .listStyle(.plain)
                .background(Color("AppBackground"))
                .scrollContentBackground(.hidden)
            }
        }
    }

    /// Navigation destinations must attach to the stack’s **inner** root (`alarmsTabMainContent`).
    /// Chaining a second `.navigationDestination` on the `NavigationStack` broke `showAddAlarm` (\+ button).
    private var alarmsTabNavigationStack: some View {
        NavigationStack {
            alarmsTabMainContent
                .navigationDestination(isPresented: $showAddAlarm) {
                    AddAlarmView(
                        preselectedDate: pendingIntentAlarmDraft?.date,
                        initialTitle: pendingIntentAlarmDraft?.label,
                        autoStartRecording: pendingIntentAlarmDraft?.shouldRecordVoice == true,
                        repeatDaysToLoad: pendingIntentAlarmDraft?.repeatDays ?? []
                    ) { date, title, snoozeEnabled, snoozeDuration, sound, repeatDays, calendarEnabled in
                        Task {
                            _ = await alarmService.scheduleFutureAlarm(
                                date: date, title: title,
                                snoozeEnabled: snoozeEnabled,
                                snoozeDuration: snoozeDuration,
                                sound: sound,
                                repeatDays: repeatDays,
                                calendarEnabled: calendarEnabled
                            )
                            await MainActor.run {
                                pendingIntentAlarmDraft = nil
                                alarmService.loadAlarms()
                            }
                        }
                    }
                }
                .navigationDestination(item: $groupToEdit) { group in
                    AddAlarmView(
                        initialTitle: group.isFired ? group.label : nil,
                        editingItem: alarmService.alarms.first(where: { group.alarmIDs.contains($0.id) }),
                        repeatDaysToLoad: group.repeatDays,
                        soundToLoad: UserDefaults.standard.string(forKey: "alarmSound_\(group.id.uuidString)") ?? "nokia.caf"
                    ) { date, title, snoozeEnabled, snoozeDuration, sound, repeatDays, calendarEnabled in
                        Task {
                            if let firstID = group.alarmIDs.first {
                                alarmService.cancelAlarm(id: firstID)
                            }
                            _ = await alarmService.scheduleFutureAlarm(
                                date: date, title: title,
                                snoozeEnabled: snoozeEnabled,
                                snoozeDuration: snoozeDuration,
                                sound: sound,
                                repeatDays: repeatDays,
                                calendarEnabled: calendarEnabled
                            )
                            UserDefaults.standard.set(sound, forKey: "alarmSound_\(group.id.uuidString)")
                            await MainActor.run { alarmService.loadAlarms() }
                        }
                    }
                }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showSettings) {
            SettingsView(preferredColorScheme: preferredColorScheme)
                .id(appColorScheme)
        }
    }

    var alarmsTab: some View {
        alarmsTabNavigationStack
            .alert("Permission Required", isPresented: $showAlarmPermissionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please allow Alarms in Settings → Date Alarm → Alarms")
            }
            .alert("Permission Required", isPresented: $showMicPermissionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please allow Microphone in Settings → Date Alarm → Microphone")
            }
            .alert("Permission Required", isPresented: $showCalendarPermissionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please allow Calendar in Settings → Date Alarm → Calendars")
            }
            .onAppear {
                alarmService.loadAlarms()
                consumePendingIntentAlarmFlowIfNeeded()
                SpotlightService.shared.indexAlarms(alarmService.alarmGroups)
                NotificationCenter.default.addObserver(forName: NSNotification.Name("showMicPermission"), object: nil, queue: .main) { _ in
                    showMicPermissionAlert = true
                }
                NotificationCenter.default.addObserver(forName: NSNotification.Name("showCalendarPermission"), object: nil, queue: .main) { _ in
                    Task { @MainActor in
                        CalendarService.shared.refreshAuthorizationStatus()
                        if CalendarService.shared.shouldShowPermissionUI {
                            showCalendarPermissionAlert = true
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                consumePendingIntentAlarmFlowIfNeeded()
                CalendarService.shared.refreshAuthorizationStatus()
                alarmService.loadAlarms()
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                    let alarmID = id.replacingOccurrences(of: "alarm_", with: "")
                    if let uuid = UUID(uuidString: alarmID),
                       let group = alarmService.alarmGroups.first(where: { $0.id == uuid }) {
                        selectedTab = 0
                        groupToEdit = group
                    }
                }
            }
    }
    
    func handleQuickAction() {
        guard let action = quickActionMode.wrappedValue else { return }
        quickActionMode.wrappedValue = nil
        switch action {
        case "newAlarm":
            selectedTab = 0; showAddAlarm = true
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

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url) { success in
                if !success {
                    showNoMailAlert = true
                }
            }
        }
    }
}
// MARK: - Alarm Group Row
struct AlarmGroupRow: View {
    let group: AlarmService.AlarmGroup
    let onToggle: () -> Void
    @State private var isHighlighted: Bool = false
    @AppStorage("use24HourFormat") private var use24Hour: Bool = false
    
    // ✅ Only this changed — added Monthly/Yearly support
    private var subtitleText: String {
        let f = DateFormatter()
        f.dateFormat = use24Hour ? "EEE, MMM d • HH:mm" : "EEE, MMM d • h:mm a"
        let tf = DateFormatter()
        tf.dateFormat = use24Hour ? "HH:mm" : "h:mm a"
        let timeOnly = group.fireDate.flatMap { tf.string(from: $0) } ?? ""
        let monthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        let dayOfMonth = group.repeatDays.filter { $0 >= 1 && $0 <= 31 }.first
        let selectedMonths = group.repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted()
        
        // ✅ Yearly — check FIRST before monthly
        let selectedYears = group.repeatDays.filter { $0 >= 2025 }.sorted()
        if !selectedYears.isEmpty {
            let dayStr = dayOfMonth.map { "\($0)" } ?? ""
            let monthStr = selectedMonths.isEmpty ? "" : monthNames[selectedMonths.sorted().first! - 101]
            let yearStr = selectedYears.count == 1 ? "\(selectedYears[0])" : "\(selectedYears.first!) → \(selectedYears.last!)"
            return "\(monthStr) \(dayStr) • \(yearStr) • \(timeOnly)"
        }
        
        // ✅ Monthly generic
        if group.repeatDays.contains(100) && selectedMonths.isEmpty {
            return "Monthly • \(timeOnly)"
        }
        
        // ✅ Monthly with selected months
        let isForever = group.repeatDays.contains(100)
        let stopYear = group.repeatDays.filter { $0 >= 201 }.first.map { $0 - 200 }
        let currentYear = Calendar.current.component(.year, from: Date())
        let repeatModeStr: String = {
            if isForever { return "Forever" }
            if let stop = stopYear { return "Until \(currentYear + stop)" }
            return "This year only"
        }()
        if !selectedMonths.isEmpty {
            let dayStr = dayOfMonth.map { "\($0)" } ?? ""
            let monthStr = selectedMonths.count == 12 ? "Every month" : selectedMonths.map { monthNames[$0 - 101] }.joined(separator: ", ")
            return "\(monthStr) • Day \(dayStr) • \(repeatModeStr) • \(timeOnly)"
        }
        if isForever {
            let dayStr = dayOfMonth.map { "\($0)" } ?? ""
            return "Every month • Day \(dayStr) • Forever • \(timeOnly)"
        }
        
        // ✅ Monthly with only day selected (no months, no forever flag, not weekly)
        let isActualWeekly = group.repeatDays.allSatisfy { $0 >= 1 && $0 <= 7 } && !group.repeatDays.isEmpty
        let hasOnlyDay = !isActualWeekly &&
        !group.repeatDays.filter { $0 >= 8 && $0 <= 31 }.isEmpty &&
        group.repeatDays.filter { $0 >= 101 && $0 <= 112 }.isEmpty &&
        !group.repeatDays.contains(100) &&
        group.repeatDays.filter { $0 >= 2025 }.isEmpty
        if hasOnlyDay {
            let day = group.repeatDays.filter { $0 >= 1 && $0 <= 31 }.first ?? 0
            let stopYear = group.repeatDays.filter { $0 >= 201 }.first.map { $0 - 200 }
            let currentYear = Calendar.current.component(.year, from: Date())
            let repeatModeStr: String = {
                if group.repeatDays.contains(100) { return "Forever" }
                if let stop = stopYear { return "Until \(currentYear + stop)" }
                return "This year only"
            }()
            return "Every month • Day \(day) • \(repeatModeStr) • \(timeOnly)"
        }
        
        // ✅ Weekly
        if group.repeatLabel.isEmpty {
            return group.fireDate.flatMap { f.string(from: $0) } ?? ""
        } else {
            let df = DateFormatter()
            df.dateFormat = "MMM d"
            let dateStr = group.fireDate.flatMap { df.string(from: $0) } ?? ""
            let weeklyPrefix = group.repeatDays.count == 7 ? "" : "Every "
            return "\(weeklyPrefix)\(group.repeatLabel) • \(dateStr) • \(timeOnly)"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // ✅ Orange header with alarm name
            HStack {
                Text(group.label.isEmpty ? "Alarm" : group.label)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(group.isEnabled ? .black : Color("SecondaryText"))
                Spacer()
                Text(subtitleText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(group.isEnabled ? Color.black.opacity(0.6) : Color("SecondaryText"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(group.isFired ? Color.green : (group.isEnabled ? Color.orange : Color("AppBackground")))
            .animation(.easeInOut(duration: 0.3), value: group.isEnabled)
            
            
            // ✅ Time + toggle row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    // Big time
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(timeText)
                            .font(.system(size: 42, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color("PrimaryText"))
                            .lineLimit(1)
                            .scaleEffect(isHighlighted ? 1.08 : 1.0)
                            .animation(.spring(response: 0.25, dampingFraction: 0.4), value: isHighlighted)
                        Text(ampmText)
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color("PrimaryText"))
                    }
                    
                    // ✅ Orange date pill
                    if group.isFired {
                        Text("Fired · Tap to reschedule")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                
                Spacer()
                
                // Toggle
                if !group.isFired {
                    Toggle("", isOn: Binding(
                        get: { group.isEnabled },
                        set: { _ in
                            onToggle()
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation {
                                isHighlighted = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) {
                                    isHighlighted = false
                                }
                            }
                        }
                    ))
                    .tint(.orange)
                    .labelsHidden()
                }
            }
            .padding(12)
            .background(Color("CardBackground"))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .opacity(group.isEnabled || group.isFired ? 1.0 : 0.5)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: group.isEnabled)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.orange.opacity(group.isFired ? 0.6 : 0), lineWidth: 2)
                .scaleEffect(group.isFired ? 1.02 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: group.isFired)
        )
    }
    
    private var timeText: String {
        let f = DateFormatter()
        f.dateFormat = use24Hour ? "HH:mm" : "h:mm"
        return group.fireDate.flatMap { f.string(from: $0) } ?? "--:--"
    }
    
    private var ampmText: String {
        guard !use24Hour else { return "" }
        let f = DateFormatter()
        f.dateFormat = "a"
        f.amSymbol = "AM"
        f.pmSymbol = "PM"
        return group.fireDate.flatMap { f.string(from: $0) } ?? ""
    }
}
// MARK: - History View
struct ScheduledView: View {
    @AppStorage("use24HourFormat") private var use24HourFormat: Bool = false
    @StateObject private var alarmService = AlarmService.shared
    @State private var expandedGroupID: UUID? = nil
    @State private var groupToEdit: AlarmService.AlarmGroup? = nil
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color("AppBackground").ignoresSafeArea()
                VStack(spacing: 0) {
                HStack {
                    Text("Scheduled")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Color("PrimaryText"))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)
                
                if alarmService.alarmGroups.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange.opacity(0.4))
                        Text("No scheduled alarms")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(Color("SecondaryText"))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 80)
                } else {
                    List {
                        ForEach(Array(alarmService.alarmGroups.enumerated()), id: \.element.id) { index, group in
                            // ✅ Main alarm card row
                            ScheduledRowView(group: group)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        expandedGroupID = expandedGroupID == group.id ? nil : group.id
                                    }
                                }
                                .listRowBackground(Color("AppBackground"))
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                            
                            // ✅ Expanded occurrence rows — each as its own List row
                            if expandedGroupID == group.id {
                                let fired = firedOccurrences(for: group)
                                let upcoming = futureOccurrences(for: group)
                                let showMore = upcoming.count > 5
                                let displayUpcoming = showMore ? Array(upcoming.prefix(5)) : upcoming
                                
                                // Fired rows
                                ForEach(Array(fired.enumerated()), id: \.offset) { _, date in
                                    FiredOccurrenceRow(date: date, group: group)
                                        .listRowBackground(Color("AppBackground"))
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 2, leading: 32, bottom: 2, trailing: 20))
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                deleteFromHistory(date: date, group: group)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                                
                                // Upcoming rows
                                ForEach(Array(displayUpcoming.enumerated()), id: \.offset) { index, date in
                                    UpcomingOccurrenceRow(date: date, group: group, isNext: index == 0)
                                    
                                        .listRowBackground(Color("AppBackground"))
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 2, leading: 32, bottom: 2, trailing: 20))
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button {
                                                groupToEdit = group
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            .tint(.orange)
                                        }
                                        .onTapGesture {
                                            groupToEdit = group
                                        }
                                }
                                
                                // More coming
                                if showMore {
                                    HStack(spacing: 6) {
                                        Image(systemName: "ellipsis.circle")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.orange.opacity(0.5))
                                        Text("more coming...")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(Color("SecondaryText").opacity(0.6))
                                    }
                                    .listRowBackground(Color("AppBackground"))
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 2, leading: 32, bottom: 6, trailing: 20))
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .background(Color("AppBackground"))
                    .scrollContentBackground(.hidden)
                }
                }
            }
            .onAppear {
                alarmService.loadAlarms()
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("EditAlarmGroup"),
                    object: nil,
                    queue: .main
                ) { notification in
                    if let group = notification.object as? AlarmService.AlarmGroup {
                        groupToEdit = group
                    }
                }
            }
            .navigationDestination(item: $groupToEdit) { group in
                AddAlarmView(
                    editingItem: alarmService.alarms.first(where: { group.alarmIDs.contains($0.id) }),
                    repeatDaysToLoad: group.repeatDays,
                    soundToLoad: UserDefaults.standard.string(forKey: "alarmSound_\(group.id.uuidString)") ?? "nokia.caf"
                ) { date, title, snoozeEnabled, snoozeDuration, sound, repeatDays, calendarEnabled in
                    Task {
                        if let firstID = group.alarmIDs.first {
                            alarmService.cancelAlarm(id: firstID)
                        }
                        _ = await alarmService.scheduleFutureAlarm(
                            date: date, title: title,
                            snoozeEnabled: snoozeEnabled,
                            snoozeDuration: snoozeDuration,
                            sound: sound,
                            repeatDays: repeatDays,
                            calendarEnabled: calendarEnabled
                        )
                        UserDefaults.standard.set(sound, forKey: "alarmSound_\(group.id.uuidString)")
                        await MainActor.run { alarmService.loadAlarms() }
                    }
                }
            }
        }
    }
    private func firedOccurrences(for group: AlarmService.AlarmGroup) -> [Date] {
        let history = AlarmService.shared.loadHistory()
        return history.compactMap { entry -> Date? in
            guard let entryLabel = entry["label"] as? String,
                  entryLabel == group.label,
                  let firedAt = entry["firedAt"] as? TimeInterval else { return nil }
            return Date(timeIntervalSince1970: firedAt)
        }.sorted()
    }
    
    private func futureOccurrences(for group: AlarmService.AlarmGroup) -> [Date] {
        guard let baseDate = group.fireDate else { return [] }
        let cal = Calendar.current
        let now = Date()
        let repeatDays = group.repeatDays
        let hour = cal.component(.hour, from: baseDate)
        let minute = cal.component(.minute, from: baseDate)
        var results: [Date] = []
        
        if repeatDays.isEmpty {
            if baseDate > now { results.append(baseDate) }
            return results
        }
        
        let isWeekly = repeatDays.allSatisfy { $0 >= 1 && $0 <= 7 } && !repeatDays.isEmpty
        if isWeekly {
            for weekOffset in 0..<12 {
                for weekday in repeatDays.sorted() {
                    var comps = DateComponents()
                    comps.weekday = weekday
                    comps.hour = hour
                    comps.minute = minute
                    comps.second = 0
                    let searchFrom = now.addingTimeInterval(TimeInterval(weekOffset * 7 * 86400) - 1)
                    if let next = cal.nextDate(after: searchFrom, matching: comps, matchingPolicy: .nextTime),
                       next > now, !results.contains(next) {
                        results.append(next)
                    }
                }
            }
            results.sort()
            return results
        }
        
        let selectedYears = repeatDays.filter { $0 >= 2025 }.sorted()
        if !selectedYears.isEmpty {
            let months = repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted()
            let day = repeatDays.filter { $0 >= 1 && $0 <= 31 }.first ?? cal.component(.day, from: baseDate)
            for year in selectedYears {
                let month = months.first.map { $0 - 100 } ?? cal.component(.month, from: baseDate)
                var comps = DateComponents()
                comps.year = year; comps.month = month; comps.day = day
                comps.hour = hour; comps.minute = minute; comps.second = 0
                if let date = cal.date(from: comps), date > now { results.append(date) }
            }
            return results
        }
        
        let selectedMonths = repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted()
        let dayOfMonth = repeatDays.filter { $0 >= 1 && $0 <= 31 }.first ?? cal.component(.day, from: baseDate)
        let isForever = repeatDays.contains(100)
        let stopAfterFlag = repeatDays.filter { $0 >= 201 && $0 < 2025 }.first
        let stopAfterYears = stopAfterFlag.map { $0 - 200 }
        let currentYear = cal.component(.year, from: now)
        let stopYear = stopAfterYears.map { currentYear + $0 } ?? (isForever ? currentYear + 10 : currentYear)
        let monthsToUse = selectedMonths.isEmpty ? Array(101...112) : selectedMonths
        
        for year in currentYear...stopYear {
            for monthCode in monthsToUse {
                let month = monthCode - 100
                var comps = DateComponents()
                comps.year = year; comps.month = month; comps.day = dayOfMonth
                comps.hour = hour; comps.minute = minute; comps.second = 0
                if let date = cal.date(from: comps), date > now { results.append(date) }
            }
        }
        return results
    }
    
    private func deleteFromHistory(date: Date, group: AlarmService.AlarmGroup) {
        var history = AlarmService.shared.loadHistory()
        history.removeAll { entry in
            guard let entryLabel = entry["label"] as? String,
                  let firedAt = entry["firedAt"] as? TimeInterval else { return false }
            return entryLabel == group.label && abs(firedAt - date.timeIntervalSince1970) < 60
        }
        if let data = try? JSONSerialization.data(withJSONObject: history),
           let json = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(json, forKey: "AlarmHistory")
            UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")?.set(json, forKey: "AlarmHistory")
        }
        alarmService.loadAlarms()
    }
}
// MARK: - Fired Occurrence Row
struct FiredOccurrenceRow: View {
    let date: Date
    let group: AlarmService.AlarmGroup
    @AppStorage("use24HourFormat") private var use24Hour: Bool = false
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = use24Hour ? "EEE, MMM d yyyy • HH:mm" : "EEE, MMM d yyyy • h:mm a"
        f.amSymbol = "AM"; f.pmSymbol = "PM"
        return f.string(from: date)
    }
    
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.green)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 14))
            Text(formatDate(date))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color("SecondaryText"))
            Spacer()
            Text("Done")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
        .background(Color("CardBackground").opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .opacity(0.6)
    }
}

// MARK: - Upcoming Occurrence Row
struct UpcomingOccurrenceRow: View {
    let date: Date
    let group: AlarmService.AlarmGroup
    @AppStorage("use24HourFormat") private var use24Hour: Bool = false
    var isNext: Bool = false
    
    private var days: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = use24Hour ? "EEE, MMM d yyyy • HH:mm" : "EEE, MMM d yyyy • h:mm a"
        f.amSymbol = "AM"; f.pmSymbol = "PM"
        return f.string(from: date)
    }
    
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.orange)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
            Image(systemName: "alarm")
                .foregroundStyle(.orange)
                .font(.system(size: 14))
            Text(formatDate(date))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color("PrimaryText"))
            Spacer()
            if days == 0 {
                Text("Today")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            } else if days == 1 {
                Text("Tomorrow")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            } else {
                Text("in \(days)d")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color("SecondaryText"))
            }
            if days == 0 || days == 1 {
                Text("Next")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            if days == 0 || days == 1 {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(Color("CardBackground"))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .opacity(isNext ? 1.0 : 0.45)
    }
}

// MARK: - Scheduled Row
struct ScheduledRowView: View {
    let group: AlarmService.AlarmGroup
    @AppStorage("use24HourFormat") private var use24Hour: Bool = false
    
    private var timeText: String {
        let f = DateFormatter()
        f.dateFormat = use24Hour ? "HH:mm" : "h:mm a"
        return group.fireDate.flatMap { f.string(from: $0) } ?? ""
    }
    
    private var dateText: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return group.fireDate.flatMap { f.string(from: $0) } ?? ""
    }
    
    private var repeatText: String {
        let monthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        if group.repeatDays == Set([100]) { return "Every month" }
        if group.repeatDays == Set([200]) { return "Every year" }
        let selectedMonths = group.repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted()
        if !selectedMonths.isEmpty { return "Monthly • \(selectedMonths.map { monthNames[$0 - 101] }.joined(separator: ", "))" }
        let selectedYears = group.repeatDays.filter { $0 >= 2025 }.sorted()
        if !selectedYears.isEmpty { return "Yearly • \(selectedYears.map { "\($0)" }.joined(separator: ", "))" }
        // ✅ Monthly with only day selected (no months, no forever flag)
        let hasOnlyDay = !group.repeatDays.filter { $0 >= 8 && $0 <= 31 }.isEmpty &&
        group.repeatDays.filter { $0 >= 101 && $0 <= 112 }.isEmpty &&
        !group.repeatDays.contains(100) &&
        group.repeatDays.filter { $0 >= 2025 }.isEmpty
        if hasOnlyDay {
            let day = group.repeatDays.filter { $0 >= 8 && $0 <= 31 }.first ?? 0
            return "Monthly • Day \(day)"
        }
        if !group.repeatDays.isEmpty { return "Weekly • \(group.repeatLabel)" }
        return ""
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Left orange line
            RoundedRectangle(cornerRadius: 3)
                .fill(.orange)
                .frame(width: 4)
                .frame(maxHeight: .infinity)
            
            VStack(alignment: .leading, spacing: 6) {
                // Alarm name
                Text(group.label)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color("PrimaryText"))
                
                // Date and time
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text("\(dateText) • \(timeText)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color("SecondaryText"))
                }
                
                // Repeat info
                if !repeatText.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "repeat")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text(repeatText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                }
            }
            
            Spacer()
            
            // Status indicator
            Circle()
                .fill(group.isEnabled ? .orange : .gray.opacity(0.3))
                .frame(width: 10, height: 10)
        }
        .padding(16)
        .background(Color("CardBackground"))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
// MARK: - Alarm Detail View
struct AlarmDetailView: View {
    let group: AlarmService.AlarmGroup
    let use24Hour: Bool
    @Environment(\.dismiss) private var dismiss
    
    private let weekDayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let monthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    
    private var firedAlarmIDs: Set<String> {
        let history = AlarmService.shared.loadHistory()
        var fired = Set(history.compactMap { $0["alarmID"] as? String })
        
        // ✅ If alarm ID is not in active alarms → it fired
        let activeAlarmIDs = Set(AlarmService.shared.alarms.map { $0.id.uuidString })
        for alarmID in group.alarmIDs {
            if !activeAlarmIDs.contains(alarmID.uuidString) {
                fired.insert(alarmID.uuidString)
            }
        }
        return fired
    }
    private var timeText: String {
        let f = DateFormatter()
        f.dateFormat = use24Hour ? "HH:mm" : "h:mm a"
        return group.fireDate.flatMap { f.string(from: $0) } ?? ""
    }
    
    var body: some View {
        ZStack {
            Color("AppBackground").ignoresSafeArea()
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color("SecondaryText").opacity(0.4))
                    .frame(width: 40, height: 5)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                
                Text(group.label)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color("PrimaryText"))
                    .padding(.bottom, 4)
                
                Text(timeText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange)
                    .padding(.bottom, 20)
                
                List {
                    ForEach(Array(group.alarmIDs.enumerated()), id: \.offset) { index, alarmID in
                        let fired = firedAlarmIDs.contains(alarmID.uuidString)
                        let alarm = AlarmService.shared.alarms.first(where: { $0.id == alarmID })
                        
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(fired ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                    .frame(width: 40, height: 40)
                                Image(systemName: fired ? "checkmark.circle.fill" : "clock.fill")
                                    .foregroundStyle(fired ? .green : .orange)
                                    .font(.system(size: 18))
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(itemLabel(index: index))
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color("PrimaryText"))
                                
                                if let fireDate = alarm?.fireDate {
                                    Text(formatDate(fireDate))
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color("SecondaryText"))
                                }
                            }
                            
                            Spacer()
                            
                            Text(fired ? "Fired" : "Pending")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(fired ? .green : .orange)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(fired ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        .padding(14)
                        .background(Color("CardBackground"))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
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
    
    private func itemLabel(index: Int) -> String {
        // Weekly
        let weekdays = group.repeatDays.filter { $0 >= 1 && $0 <= 7 }.sorted()
        if !weekdays.isEmpty && index < weekdays.count {
            return weekDayNames[weekdays[index] - 1]
        }
        // Monthly with months
        let months = group.repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted()
        if !months.isEmpty && index < months.count {
            return monthNames[months[index] - 101]
        }
        // Yearly with years
        let years = group.repeatDays.filter { $0 >= 2025 }.sorted()
        if !years.isEmpty && index < years.count {
            return "\(years[index])"
        }
        return "Alarm \(index + 1)"
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = use24Hour ? "EEE, MMM d • HH:mm" : "EEE, MMM d • h:mm a"
        return f.string(from: date)
    }
}
// MARK: - Alarm Detail Inline View
struct AlarmDetailInlineView: View {
    let group: AlarmService.AlarmGroup
    let use24Hour: Bool
    
    private let monthNames = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    
    private func firedOccurrences() -> [Date] {
        let history = AlarmService.shared.loadHistory()
        return history.compactMap { entry -> Date? in
            guard let entryLabel = entry["label"] as? String,
                  entryLabel == group.label,
                  let firedAt = entry["firedAt"] as? TimeInterval else { return nil }
            return Date(timeIntervalSince1970: firedAt)
        }.sorted()
    }
    
    private func futureOccurrences() -> [Date] {
        guard let baseDate = group.fireDate else { return [] }
        let cal = Calendar.current
        let now = Date()
        let repeatDays = group.repeatDays
        let hour = cal.component(.hour, from: baseDate)
        let minute = cal.component(.minute, from: baseDate)
        var results: [Date] = []
        
        // ONE-TIME
        if repeatDays.isEmpty {
            if baseDate > now { results.append(baseDate) }
            return results
        }
        
        // WEEKLY
        let isWeekly = repeatDays.allSatisfy { $0 >= 1 && $0 <= 7 } && !repeatDays.isEmpty
        if isWeekly {
            for weekOffset in 0..<6 {
                for weekday in repeatDays.sorted() {
                    var comps = DateComponents()
                    comps.weekday = weekday
                    comps.hour = hour
                    comps.minute = minute
                    comps.second = 0
                    let searchFrom = now.addingTimeInterval(TimeInterval(weekOffset * 7 * 86400) - 1)
                    if let next = cal.nextDate(after: searchFrom, matching: comps, matchingPolicy: .nextTime),
                       next > now, !results.contains(next) {
                        results.append(next)
                    }
                }
            }
            results.sort()
            return Array(results.prefix(5))
        }
        
        // YEARLY specific years
        let selectedYears = repeatDays.filter { $0 >= 2025 }.sorted()
        if !selectedYears.isEmpty {
            let months = repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted()
            let day = repeatDays.filter { $0 >= 1 && $0 <= 31 }.first ?? cal.component(.day, from: baseDate)
            for year in selectedYears {
                let month = months.first.map { $0 - 100 } ?? cal.component(.month, from: baseDate)
                var comps = DateComponents()
                comps.year = year; comps.month = month; comps.day = day
                comps.hour = hour; comps.minute = minute; comps.second = 0
                if let date = cal.date(from: comps), date > now {
                    results.append(date)
                }
            }
            return results
        }
        
        // MONTHLY
        let selectedMonths = repeatDays.filter { $0 >= 101 && $0 <= 112 }.sorted()
        let dayOfMonth = repeatDays.filter { $0 >= 1 && $0 <= 31 }.first ?? cal.component(.day, from: baseDate)
        let isForever = repeatDays.contains(100)
        let stopAfterFlag = repeatDays.filter { $0 >= 201 && $0 < 2025 }.first
        let stopAfterYears = stopAfterFlag.map { $0 - 200 }
        let currentYear = cal.component(.year, from: now)
        let stopYear = stopAfterYears.map { currentYear + $0 } ?? (isForever ? currentYear + 10 : currentYear)
        let monthsToUse = selectedMonths.isEmpty ? Array(101...112) : selectedMonths
        
        for year in currentYear...stopYear {
            for monthCode in monthsToUse {
                let month = monthCode - 100
                var comps = DateComponents()
                comps.year = year; comps.month = month; comps.day = dayOfMonth
                comps.hour = hour; comps.minute = minute; comps.second = 0
                if let date = cal.date(from: comps), date > now {
                    results.append(date)
                }
            }
        }
        return results
    }
    
    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = use24Hour ? "EEE, MMM d yyyy • HH:mm" : "EEE, MMM d yyyy • h:mm a"
        f.amSymbol = "AM"; f.pmSymbol = "PM"
        return f.string(from: date)
    }
    
    private func daysUntil(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
    }
    
    var body: some View {
        let fired = firedOccurrences()
        let upcoming = futureOccurrences()
        let showMore = upcoming.count > 5
        let displayUpcoming = showMore ? Array(upcoming.prefix(5)) : upcoming
        
        VStack(spacing: 4) {
            ForEach(Array(fired.enumerated()), id: \.offset) { index, date in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green)
                        .frame(width: 3)
                        .frame(maxHeight: .infinity)
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 14))
                    Text(formatDate(date))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color("SecondaryText"))
                    Spacer()
                    Text("Done")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(12)
                .background(Color("CardBackground").opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .opacity(0.6)
                .contextMenu {
                    Button(role: .destructive) {
                        var history = AlarmService.shared.loadHistory()
                        history.removeAll { entry in
                            guard let entryLabel = entry["label"] as? String,
                                  let firedAt = entry["firedAt"] as? TimeInterval else { return false }
                            return entryLabel == group.label &&
                            abs(firedAt - date.timeIntervalSince1970) < 60
                        }
                        if let data = try? JSONSerialization.data(withJSONObject: history),
                           let json = String(data: data, encoding: .utf8) {
                            UserDefaults.standard.set(json, forKey: "AlarmHistory")
                            let appGroup = UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")
                            appGroup?.set(json, forKey: "AlarmHistory")
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            
            ForEach(Array(displayUpcoming.enumerated()), id: \.offset) { _, date in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.orange)
                        .frame(width: 3)
                        .frame(maxHeight: .infinity)
                    Image(systemName: "alarm")
                        .foregroundStyle(.orange)
                        .font(.system(size: 14))
                    Text(formatDate(date))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color("PrimaryText"))
                    Spacer()
                    let days = daysUntil(date)
                    if days == 0 {
                        Text("Today")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                    } else if days == 1 {
                        Text("Tomorrow")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                    } else {
                        Text("in \(days)d")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color("SecondaryText"))
                    }
                    if days == 0 || days == 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(12)
                .background(Color("CardBackground"))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
                .onTapGesture {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("EditAlarmGroup"),
                        object: group
                    )
                }
                .contextMenu {
                    Button {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("EditAlarmGroup"),
                            object: group
                        )
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }
            }
            
            if showMore {
                HStack(spacing: 6) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange.opacity(0.5))
                    Text("more coming...")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color("SecondaryText").opacity(0.6))
                }
                .padding(.top, 2)
            }
        }
        .padding(.top, 4)
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }
}
