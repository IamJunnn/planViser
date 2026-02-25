import SwiftUI
import SwiftData

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case accounts = "Accounts"
    case appearance = "Appearance"
    case aiMonitor = "AI Monitor"
    case weeklyReview = "Weekly Review"
    case security = "Security"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .accounts: return "person.crop.circle"
        case .appearance: return "textformat.size"
        case .aiMonitor: return "eye"
        case .weeklyReview: return "doc.text.magnifyingglass"
        case .security: return "lock.shield"
        }
    }
}

struct SettingsView: View {
    @Query private var accounts: [EmailAccount]
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var gmailAuth = GmailAuthService.shared
    @ObservedObject private var outlookAuth = OutlookAuthService.shared
    @ObservedObject private var imapAuth = IMAPAuthService.shared
    @ObservedObject private var screenMonitor = ScreenMonitorManager.shared
    @AppStorage("appFontSize") private var fontSizeStep: Double = 3
    @AppStorage("noteUnlockDuration") private var noteUnlockDuration: Int = 15

    @ObservedObject private var unlockManager = NoteUnlockManager.shared
    @ObservedObject private var appUpdater = AppUpdater.shared

    @State private var apiKeyInput = ""
    @State private var hasStoredKey = false
    @State private var showActivityLog = false
    @State private var showIMAPSetup = false
    @State private var selectedTab: SettingsTab = .general

    @AppStorage("reviewNotificationHour") private var reviewHour: Int = 10
    @AppStorage("reviewNotificationMinute") private var reviewMinute: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .scaledFont(.caption)
                            Text(tab.rawValue)
                                .scaledFont(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.2) : Color.clear)
                        .cornerRadius(6)
                        .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Tab content
            ScrollView {
                switch selectedTab {
                case .general:
                    generalTab
                case .accounts:
                    accountsTab
                case .appearance:
                    appearanceTab
                case .aiMonitor:
                    aiMonitorTab
                case .weeklyReview:
                    weeklyReviewTab
                case .security:
                    securityTab
                }
            }
        }
        .onAppear {
            hasStoredKey = ClaudeVisionService.shared.getAPIKey() != nil
            // Reconcile: ensure auth-service accounts have matching SwiftData records
            for accountInfo in gmailAuth.connectedAccounts {
                addAccount(provider: .gmail, email: accountInfo.email, name: accountInfo.displayName)
            }
            for accountInfo in outlookAuth.connectedAccounts {
                addAccount(provider: .outlook, email: accountInfo.email, name: accountInfo.displayName)
            }
            for accountInfo in imapAuth.connectedAccounts {
                addAccount(provider: .imap, email: accountInfo.email, name: accountInfo.displayName)
            }
        }
        .onChange(of: gmailAuth.connectedAccounts) { _, newAccounts in
            for accountInfo in newAccounts {
                addAccount(provider: .gmail, email: accountInfo.email, name: accountInfo.displayName)
            }
        }
        .onChange(of: outlookAuth.connectedAccounts) { _, newAccounts in
            for accountInfo in newAccounts {
                addAccount(provider: .outlook, email: accountInfo.email, name: accountInfo.displayName)
            }
        }
        .onChange(of: imapAuth.connectedAccounts) { _, newAccounts in
            for accountInfo in newAccounts {
                addAccount(provider: .imap, email: accountInfo.email, name: accountInfo.displayName)
            }
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Updates")
                .scaledFont(.headline)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Planviser v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                        .scaledFont(.subheadline)
                    Text("Automatically checks for updates on launch")
                        .scaledFont(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Check for Updates") {
                    appUpdater.checkForUpdates()
                }
                .buttonStyle(.bordered)
                .disabled(!appUpdater.canCheckForUpdates)
            }
        }
        .padding()
    }

    // MARK: - Accounts Tab

    private var accountsTab: some View {
        VStack(spacing: 16) {
            Text("Connected Accounts")
                .scaledFont(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 12)

            if accounts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .scaledFont(size: 36)
                        .foregroundColor(.secondary)
                    Text("No accounts connected")
                        .scaledFont(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: 100)
            } else {
                VStack(spacing: 0) {
                    ForEach(accounts) { account in
                        AccountRowView(account: account, modelContext: modelContext, onDisconnect: {
                            disconnectAccount(account)
                        })
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }

            Divider()

            VStack(spacing: 8) {
                Button("Connect Gmail") {
                    gmailAuth.signIn()
                }
                .buttonStyle(.borderedProminent)

                Button("Connect Outlook") {
                    outlookAuth.signIn()
                }
                .buttonStyle(.bordered)

                Button("Connect IMAP / Exchange") {
                    showIMAPSetup = true
                }
                .buttonStyle(.bordered)
                .sheet(isPresented: $showIMAPSetup) {
                    IMAPSetupSheet()
                }

                Button("Reset Calendar") {
                    EmailSyncService.shared.resetAllMeetings(modelContext: modelContext)
                }
                .scaledFont(.caption)
                .foregroundColor(.red)
                .buttonStyle(.plain)
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Font Size")
                .scaledFont(.headline)

            HStack {
                Text("A").font(.system(size: 12))
                Slider(value: $fontSizeStep, in: 0...6, step: 1)
                Text("A").font(.system(size: 24))
            }

            Text("The quick brown fox jumps over the lazy dog.")
                .scaledFont(.body)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    // MARK: - AI Monitor Tab

    private var aiMonitorTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Screen Monitor")
                .scaledFont(.headline)

            // Permission status
            HStack(spacing: 6) {
                Circle()
                    .fill(screenMonitor.hasPermission ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(screenMonitor.hasPermission ? "Screen recording permitted" : "Screen recording not permitted")
                    .scaledFont(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if !screenMonitor.hasPermission {
                    Button("Open Privacy Settings") {
                        screenMonitor.openPrivacySettings()
                    }
                    .scaledFont(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Enable toggle
            Toggle("Enable monitoring", isOn: Binding(
                get: { screenMonitor.isEnabled },
                set: { _ in screenMonitor.toggle() }
            ))
            .scaledFont(.subheadline)
            .disabled(!hasStoredKey || !screenMonitor.hasPermission)

            // Interval stepper
            Stepper(
                "Interval: \(screenMonitor.intervalMinutes) min",
                value: Binding(
                    get: { screenMonitor.intervalMinutes },
                    set: { screenMonitor.setInterval(minutes: $0) }
                ),
                in: 1...30
            )
            .scaledFont(.subheadline)

            // API Key
            VStack(alignment: .leading, spacing: 4) {
                Text("Anthropic API Key")
                    .scaledFont(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    if hasStoredKey {
                        Text("••••••••••••••••")
                            .scaledFont(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Clear") {
                            ClaudeVisionService.shared.clearAPIKey()
                            hasStoredKey = false
                            apiKeyInput = ""
                        }
                        .scaledFont(.caption)
                        .foregroundColor(.red)
                        .buttonStyle(.plain)
                    } else {
                        SecureField("sk-ant-...", text: $apiKeyInput)
                            .scaledFont(.subheadline)
                            .textFieldStyle(.roundedBorder)

                        Button("Save") {
                            guard !apiKeyInput.isEmpty else { return }
                            ClaudeVisionService.shared.saveAPIKey(apiKeyInput)
                            hasStoredKey = true
                            apiKeyInput = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(apiKeyInput.isEmpty)
                    }
                }
            }

            // Analyze Now + Last Error
            HStack {
                Button {
                    Task {
                        await screenMonitor.captureAndAnalyzeNow()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if screenMonitor.isCapturing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(screenMonitor.isCapturing ? "Analyzing..." : "Analyze Now")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(screenMonitor.isCapturing || !hasStoredKey || !screenMonitor.hasPermission)

                if let error = screenMonitor.lastError {
                    Text(error)
                        .scaledFont(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }

            // Activity Log
            DisclosureGroup("Activity Log (\(screenMonitor.activityLog.count))", isExpanded: $showActivityLog) {
                if screenMonitor.activityLog.isEmpty {
                    Text("No activity detected yet")
                        .scaledFont(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(screenMonitor.activityLog.prefix(10)) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(entry.timestamp, style: .time)
                                        .scaledFont(.caption2)
                                        .foregroundColor(.secondary)
                                    if let taskTitle = entry.matchedTaskTitle {
                                        Text("→ \(taskTitle)")
                                            .scaledFont(.caption2, weight: .medium)
                                            .foregroundColor(.purple)
                                    }
                                    Spacer()
                                    Text("\(Int(entry.confidence * 100))%")
                                        .scaledFont(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Text(entry.summary)
                                    .scaledFont(.caption)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                            Divider()
                        }
                    }
                }
            }
            .scaledFont(.subheadline)
        }
        .padding()
    }

    // MARK: - Weekly Review Tab

    private var weeklyReviewTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Weekly Review Notification")
                .scaledFont(.headline)

            Text("Get reminded to do your weekly review every Sunday.")
                .scaledFont(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Text("Reminder time:")
                    .scaledFont(.subheadline)

                Picker("Hour", selection: $reviewHour) {
                    ForEach(0..<24, id: \.self) { h in
                        Text(hourLabel(h)).tag(h)
                    }
                }
                .frame(width: 100)

                Picker("Minute", selection: $reviewMinute) {
                    ForEach([0, 15, 30, 45], id: \.self) { m in
                        Text(String(format: "%02d", m)).tag(m)
                    }
                }
                .frame(width: 70)
            }
            .onChange(of: reviewHour) { _, _ in
                WeeklyReviewService.shared.scheduleSundayNotification()
            }
            .onChange(of: reviewMinute) { _, _ in
                WeeklyReviewService.shared.scheduleSundayNotification()
            }

            Text("Currently set to \(hourLabel(reviewHour)):\(String(format: "%02d", reviewMinute))")
                .scaledFont(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    // MARK: - Security Tab

    private var securityTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Secure Notes")
                .scaledFont(.headline)

            // Biometric status
            HStack(spacing: 6) {
                Image(systemName: unlockManager.isUnlocked ? "lock.open.fill" : "lock.fill")
                    .foregroundColor(unlockManager.isUnlocked ? .green : .secondary)
                Text(unlockManager.isUnlocked ? "Notes unlocked" : "Notes locked")
                    .scaledFont(.subheadline)
            }

            // Unlock duration picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Auto-lock after:")
                    .scaledFont(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(UnlockDuration.allCases) { duration in
                    HStack(spacing: 8) {
                        Image(systemName: noteUnlockDuration == duration.rawValue ? "circle.inset.filled" : "circle")
                            .foregroundColor(noteUnlockDuration == duration.rawValue ? .accentColor : .secondary)
                            .font(.system(size: 14))
                        Text(duration.label)
                            .scaledFont(.subheadline)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        noteUnlockDuration = duration.rawValue
                    }
                }
            }

            // Manual lock button
            if unlockManager.isUnlocked {
                Button(action: { unlockManager.lock() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                        Text("Lock Now")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }

    // MARK: - Helpers

    private func addAccount(provider: EmailProvider, email: String, name: String) {
        let exists = accounts.contains { $0.provider == provider && $0.email == email }
        if exists { return }

        let account = EmailAccount(provider: provider, email: email, displayName: name)
        modelContext.insert(account)
        try? modelContext.save()
    }

    private func disconnectAccount(_ account: EmailAccount) {
        switch account.provider {
        case .gmail:
            gmailAuth.signOut(email: account.email)
        case .outlook:
            outlookAuth.signOut(email: account.email)
        case .imap:
            imapAuth.signOut(email: account.email)
        }
        modelContext.delete(account)
        try? modelContext.save()
    }
}

struct AccountRowView: View {
    @Bindable var account: EmailAccount
    var modelContext: ModelContext
    var onDisconnect: () -> Void

    var body: some View {
        HStack {
            Image(systemName: account.provider == .imap ? "server.rack" : (account.provider == .gmail ? "envelope" : "envelope.badge"))
                .foregroundColor(account.color)
            VStack(alignment: .leading) {
                Text(account.email)
                    .scaledFont(.subheadline)
                Text(account.provider.rawValue.capitalized)
                    .scaledFont(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()

            ColorPicker("", selection: Binding(
                get: { account.color },
                set: { newColor in
                    account.colorHex = newColor.hexString
                    try? modelContext.save()
                }
            ))
            .labelsHidden()
            .frame(width: 24, height: 24)

            Circle()
                .fill(account.status == .connected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Button("Disconnect") {
                onDisconnect()
            }
            .scaledFont(.caption)
            .foregroundColor(.red)
            .buttonStyle(.plain)
        }
    }
}
