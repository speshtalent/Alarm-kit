import SwiftUI

// MARK: - Settings View
struct SettingsView: View {
    @AppStorage("alarmNotificationsEnabled") private var alarmNotificationsEnabled: Bool = false
    @AppStorage("appColorScheme") private var appColorScheme: String = "system"
    @AppStorage("use24HourFormat") private var use24HourFormat: Bool = false
    @AppStorage("selectedAppIcon") private var selectedAppIcon: String = "Classic"
    @AppStorage("globalSnoozeEnabled") private var globalSnoozeEnabled: Bool = true
    @AppStorage("globalSnoozeDuration") private var globalSnoozeDuration: Int = 5
    @State private var showRemoveCalendarAlert = false
    @State private var showClearCloudAlert = false
    @State private var showClearCloudSuccess = false
    @State private var showRestoreAlert = false
    @State private var showRestoreSuccessAlert = false
    @State private var showNoBackupAlert = false
    @State private var isRestoring = false
    @State private var pendingIcon: String = "Classic"
    @State private var showFeatureRequest = false
    @State private var showShareSheet = false
    @State private var showNotificationPermissionAlert = false
    @State private var calendarEventCount: Int = UserDefaults.standard.dictionary(forKey: "calendarEventMap")?.count ?? 0
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.dismiss) private var dismiss

    var preferredColorScheme: ColorScheme?

    private let appIcons: [(name: String, imageName: String, iconName: String?)] = [
        ("Storm", "AppIcon", nil),
        ("Blaze", "AppIcon1", "AppIcon1"),
    ]

    /// App Store product page (used by Share App → `UIActivityViewController`).
    private let appStoreListingURL = URL(string: "https://apps.apple.com/us/app/date-alarm/id6761073513")!

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
                VStack(spacing: 0) {

                    RoundedRectangle(cornerRadius: 3)
                        .fill(secondaryText.opacity(0.4))
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)
                        .padding(.bottom, 16)

                    Text("Settings")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(primaryText)
                        .padding(.bottom, 20)

                    // MARK: — Display Section
                    sectionHeader("Display")

                    VStack(spacing: 0) {
                        // Appearance
                        settingsRow(
                            icon: "circle.lefthalf.filled",
                            title: "Appearance",
                            subtitle: appColorScheme == "system" ? "System default" : (appColorScheme == "dark" ? "Dark mode" : "Light mode")
                        ) {
                            // expanded inline
                        }
                        .overlay(alignment: .trailing) {
                            Toggle("", isOn: useSystemDefault)
                                .tint(.orange)
                                .padding(.trailing, 16)
                                .labelsHidden()
                        }

                        if appColorScheme != "system" {
                            Divider().padding(.leading, 16)
                            appearanceRow(title: "Light Mode", subtitle: "Classic look", value: "light")
                            Divider().padding(.leading, 16)
                            appearanceRow(title: "Dark Mode", subtitle: "Easy on the eyes", value: "dark")
                        }

                        Divider().padding(.leading, 16)

                        // App Icon
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.orange)
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "app.fill")
                                        .foregroundStyle(.white)
                                        .font(.system(size: 15))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("App Icon")
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundStyle(primaryText)
                                    Text("Currently: \(selectedAppIcon)")
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundStyle(secondaryText)
                                }
                                Spacer()
                            }
                            .padding(16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(appIcons, id: \.name) { icon in
                                        VStack(spacing: 8) {
                                            Group {
                                                if let uiImage = UIImage(named: icon.imageName) {
                                                    Image(uiImage: uiImage).resizable().scaledToFit()
                                                } else {
                                                    RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.2))
                                                }
                                            }
                                            .frame(width: 56, height: 56)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(pendingIcon == icon.name ? Color.orange : Color.clear, lineWidth: 2.5)
                                            )
                                            Text(icon.name)
                                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                                .foregroundStyle(pendingIcon == icon.name ? .orange : secondaryText)
                                            if selectedAppIcon == icon.name {
                                                Text("Active")
                                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.3)) { pendingIcon = icon.name }
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                            }

                            if pendingIcon != selectedAppIcon {
                                Button { applyIcon() } label: {
                                    Text("Apply")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(.black)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color.orange)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                                .transition(.opacity)
                            }
                        }

                        Divider().padding(.leading, 16)

                        // Time Format
                        settingsRow(
                            icon: "clock.fill",
                            title: "24 Hour Time",
                            subtitle: use24HourFormat ? "Using 24hr format" : "Using 12hr format"
                        ) {}
                        .overlay(alignment: .trailing) {
                            Toggle("", isOn: $use24HourFormat)
                                .tint(.orange)
                                .padding(.trailing, 16)
                                .labelsHidden()
                                .onChange(of: use24HourFormat) {
                                    AlarmService.shared.saveNextAlarmForWidget()
                                }
                        }
                    }
                    .background(cardColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                    // MARK: — Alarm Section
                    sectionHeader("Alarm")

                    VStack(spacing: 0) {
                        // Notifications
                        settingsRow(
                            icon: "bell.fill",
                            title: "Notifications",
                            subtitle: "10 mins before & day before"
                        ) {}
                        .overlay(alignment: .trailing) {
                            Toggle("", isOn: $alarmNotificationsEnabled)
                                .tint(.orange)
                                .padding(.trailing, 16)
                                .labelsHidden()
                                .onChange(of: alarmNotificationsEnabled) { _, newValue in
                                    if newValue {
                                        Task {
                                            let settings = await UNUserNotificationCenter.current().notificationSettings()
                                            if settings.authorizationStatus == .denied {
                                                showNotificationPermissionAlert = true
                                            } else {
                                                NotificationService.shared.requestPermission()
                                            }
                                        }
                                    }
                                }
                        }

                        Divider().padding(.leading, 16)

                        // Snooze
                        settingsRow(
                            icon: "moon.zzz.fill",
                            title: "Snooze",
                            subtitle: globalSnoozeEnabled ? "\(globalSnoozeDuration) min default" : "Disabled"
                        ) {}
                        .overlay(alignment: .trailing) {
                            Toggle("", isOn: $globalSnoozeEnabled)
                                .tint(.orange)
                                .padding(.trailing, 16)
                                .labelsHidden()
                        }

                        if globalSnoozeEnabled {
                            Divider().padding(.leading, 16)
                            HStack {
                                Text("Default Duration")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundStyle(secondaryText)
                                Spacer()
                                Stepper("\(globalSnoozeDuration) min", value: $globalSnoozeDuration, in: 1...30)
                                    .foregroundStyle(primaryText)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .onChange(of: globalSnoozeDuration) { _, newValue in
                                        let appGroup = UserDefaults(suiteName: "group.com.speshtalent.FutureAlarm26")
                                        appGroup?.set(newValue, forKey: "globalSnoozeDuration")
                                    }
                            }
                            .padding(16)
                        }
                    }
                    .background(cardColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                    // MARK: — Data Section
                    sectionHeader("Data & Backup")

                    let hasCloudData = NSUbiquitousKeyValueStore.default.data(forKey: "iCloudAlarmBackup") != nil
                    let hasCalendarEvents = calendarEventCount > 0

                    VStack(spacing: 0) {
                        // Restore iCloud
                        settingsRow(
                            icon: "icloud.and.arrow.down.fill",
                            title: "Restore from iCloud",
                            subtitle: hasCloudData ? "Backup available" : "No backup found"
                        ) {
                            let store = NSUbiquitousKeyValueStore.default
                            store.synchronize()
                            if store.data(forKey: "iCloudAlarmBackup") != nil {
                                showRestoreAlert = true
                            } else {
                                showNoBackupAlert = true
                            }
                        }
                        .overlay(alignment: .trailing) {
                            Group {
                                if isRestoring {
                                    ProgressView().tint(.orange)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(secondaryText)
                                        .font(.system(size: 13))
                                }
                            }
                            .padding(.trailing, 16)
                        }

                        Divider().padding(.leading, 16)

                        // Clear iCloud
                        settingsRow(
                            icon: "icloud.fill",
                            title: "Clear iCloud Backup",
                            subtitle: hasCloudData ? "Active backup" : "No backup"
                        ) {
                            if hasCloudData { showClearCloudAlert = true }
                        }
                        .opacity(hasCloudData ? 1.0 : 0.4)
                        .overlay(alignment: .trailing) {
                            Text(hasCloudData ? "Active" : "Empty")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(hasCloudData ? .orange : secondaryText)
                                .padding(.trailing, 16)
                        }

                        Divider().padding(.leading, 16)

                        // Calendar Events
                        settingsRow(
                            icon: "calendar.badge.minus",
                            title: "Remove Calendar Events",
                            subtitle: hasCalendarEvents ? "\(calendarEventCount) events active" : "No events"
                        ) {
                            if hasCalendarEvents { showRemoveCalendarAlert = true }
                        }
                        .opacity(hasCalendarEvents ? 1.0 : 0.4)
                        .overlay(alignment: .trailing) {
                            Text(hasCalendarEvents ? "Active" : "Empty")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(hasCalendarEvents ? .orange : secondaryText)
                                .padding(.trailing, 16)
                        }
                    }
                    .background(cardColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                    // MARK: — About Section
                    sectionHeader("About")

                    VStack(spacing: 0) {
                        settingsRow(icon: "square.and.arrow.up.fill", title: "Share App", subtitle: "Tell your friends") {
                            showShareSheet = true
                        }
                        .overlay(alignment: .trailing) {
                            Image(systemName: "chevron.right").foregroundStyle(secondaryText).font(.system(size: 13)).padding(.trailing, 16)
                        }
                        .sheet(isPresented: $showShareSheet) {
                            ShareSheet(items: ["Check out Date Alarm! 🔔", appStoreListingURL])
                        }

                        Divider().padding(.leading, 16)

                        settingsRow(icon: "lightbulb.fill", title: "Request a Feature", subtitle: "We'd love your ideas") {
                            showFeatureRequest = true
                        }
                        .overlay(alignment: .trailing) {
                            Image(systemName: "chevron.right").foregroundStyle(secondaryText).font(.system(size: 13)).padding(.trailing, 16)
                        }

                        Divider().padding(.leading, 16)

                        settingsRow(icon: "lock.shield.fill", title: "Privacy & Security", subtitle: "View our privacy policy") {
                            if let url = URL(string: "https://speshtalent.com/datealarm") {
                                UIApplication.shared.open(url)
                            }
                        }
                        .overlay(alignment: .trailing) {
                            Image(systemName: "chevron.right").foregroundStyle(secondaryText).font(.system(size: 13)).padding(.trailing, 16)
                        }

                        Divider().padding(.leading, 16)

                        settingsRow(icon: "info.circle.fill", title: "Version", subtitle: appVersion) {}
                    }
                    .background(cardColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(currentColorScheme)
        .onAppear {
            pendingIcon = selectedAppIcon
            calendarEventCount = UserDefaults.standard.dictionary(forKey: "calendarEventMap")?.count ?? 0
        }
        .alert("Remove All Calendar Events?", isPresented: $showRemoveCalendarAlert) {
            Button("Remove", role: .destructive) {
                CalendarService.shared.removeAllCalendarEvents()
                let alarmService = AlarmService.shared
                for group in alarmService.alarmGroups {
                    let groupUUID = group.id
                    let alarmIDs = alarmService.getAlarmIDs(forGroup: groupUUID)
                    let idsToDisable = alarmIDs.isEmpty ? group.alarmIDs : alarmIDs
                    for alarmID in idsToDisable {
                        if alarmService.alarms.first(where: { $0.id == alarmID })?.isEnabled == true {
                            alarmService.toggleAlarm(id: alarmID)
                        }
                    }
                }
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await MainActor.run {
                        alarmService.loadAlarms()
                        calendarEventCount = 0
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all calendar events and disable all alarms.")
        }
        .alert("Clear All Data?", isPresented: $showClearCloudAlert) {
            Button("Yes, Delete Everything", role: .destructive) {
                let store = NSUbiquitousKeyValueStore.default
                store.removeObject(forKey: "iCloudAlarmBackup")
                store.removeObject(forKey: "customRecordingsList")
                store.synchronize()
                UserDefaults.standard.removeObject(forKey: "hasLaunchedBefore")
                let saved = UserDefaults.standard.array(forKey: "customRecordingsList") as? [[String: String]] ?? []
                let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                for recording in saved {
                    if let file = recording["file"] {
                        let url = libraryURL.appendingPathComponent("Sounds/\(file)")
                        try? FileManager.default.removeItem(at: url)
                    }
                }
                UserDefaults.standard.removeObject(forKey: "customRecordingsList")
                let allKeys = UserDefaults.standard.dictionaryRepresentation().keys
                for key in allKeys {
                    if key.hasPrefix("voiceRecordingName_") || key.hasPrefix("voiceRecordingFile_") {
                        UserDefaults.standard.removeObject(forKey: key)
                    }
                    if key.hasPrefix("alarmSound_") {
                        let value = UserDefaults.standard.string(forKey: key) ?? ""
                        if value.hasPrefix("custom_voice_") || value.hasPrefix("alarm_voice_") {
                            UserDefaults.standard.removeObject(forKey: key)
                        }
                    }
                }
                showClearCloudSuccess = true
            }
            Button("No", role: .cancel) {}
        } message: {
            Text("This will permanently delete all your recordings and iCloud backup data. This cannot be undone.")
        }
        .alert("iCloud Backup Cleared", isPresented: $showClearCloudSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your iCloud backup has been successfully cleared.")
        }
        .alert("Restore from iCloud?", isPresented: $showRestoreAlert) {
            Button("Yes, Restore") {
                isRestoring = true
                Task {
                    UserDefaults.standard.removeObject(forKey: "hasLaunchedBefore")
                    await AlarmService.shared.requestAuthorizationIfNeeded()
                    let restored = await AlarmService.shared.restoreFromiCloudIfNeeded()
                    await MainActor.run {
                        isRestoring = false
                        AlarmService.shared.loadAlarms()
                        if restored { showRestoreSuccessAlert = true } else { showNoBackupAlert = true }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore your previously backed up alarms and recordings from iCloud.")
        }
        .alert("Restore Complete ✅", isPresented: $showRestoreSuccessAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your alarms have been restored from iCloud successfully!")
        }
        .alert("No Backup Found", isPresented: $showNoBackupAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No iCloud backup was found, or your alarms have already been restored.")
        }
        .alert("Permission Required", isPresented: $showNotificationPermissionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please allow Notifications in Settings → Date Alarm → Notifications")
        }
        .sheet(isPresented: $showFeatureRequest) {
            FeatureRequestView()
                .preferredColorScheme(currentColorScheme)
        }
    }

    // MARK: - Section Header
    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
                .tracking(0.8)
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    // MARK: - Settings Row
    @ViewBuilder
    private func settingsRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .foregroundStyle(.white)
                    .font(.system(size: 15))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)
                Text(subtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(secondaryText)
            }
            Spacer()
        }
        .padding(16)
        .contentShape(Rectangle())
        .onTapGesture { action() }
    }

    // MARK: - Appearance Row
    @ViewBuilder
    private func appearanceRow(title: String, subtitle: String, value: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(appColorScheme == value ? Color.orange : secondaryText.opacity(0.3))
                    .frame(width: 32, height: 32)
                Image(systemName: value == "light" ? "sun.max.fill" : "moon.fill")
                    .foregroundStyle(.white)
                    .font(.system(size: 15))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryText)
                Text(subtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(secondaryText)
            }
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

    private func applyIcon() {
        guard let icon = appIcons.first(where: { $0.name == pendingIcon }) else { return }
        UIApplication.shared.setAlternateIconName(icon.iconName) { error in
            if let error = error {
                print("❌ Error: \(error.localizedDescription)")
            } else {
                print("✅ Icon changed successfully!")
                DispatchQueue.main.async {
                    selectedAppIcon = pendingIcon
                }
            }
        }
    }
}
