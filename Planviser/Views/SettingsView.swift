import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var accounts: [EmailAccount]
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var gmailAuth = GmailAuthService.shared
    @ObservedObject private var outlookAuth = OutlookAuthService.shared

    var body: some View {
        VStack(spacing: 16) {
            Text("Connected Accounts")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 12)

            if accounts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No accounts connected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(accounts) { account in
                    AccountRowView(account: account, onDisconnect: {
                        disconnectAccount(account)
                    })
                }
            }

            Divider()

            VStack(spacing: 8) {
                // Gmail
                if gmailAuth.isAuthenticated {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Gmail connected")
                            .font(.caption)
                    }
                } else {
                    Button("Connect Gmail") {
                        gmailAuth.signIn()
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Outlook
                if outlookAuth.isAuthenticated {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Outlook connected")
                            .font(.caption)
                    }
                } else {
                    Button("Connect Outlook") {
                        outlookAuth.signIn()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.bottom, 12)
        }
        .onChange(of: gmailAuth.userEmail) { _, newEmail in
            if let email = newEmail {
                addAccount(provider: .gmail, email: email, name: gmailAuth.userName ?? email)
            }
        }
        .onChange(of: outlookAuth.userEmail) { _, newEmail in
            if let email = newEmail {
                addAccount(provider: .outlook, email: email, name: outlookAuth.userName ?? email)
            }
        }
    }

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
            gmailAuth.signOut()
        case .outlook:
            outlookAuth.signOut()
        }
        modelContext.delete(account)
        try? modelContext.save()
    }
}

struct AccountRowView: View {
    let account: EmailAccount
    var onDisconnect: () -> Void

    var body: some View {
        HStack {
            Image(systemName: account.provider == .gmail ? "envelope" : "envelope.badge")
                .foregroundColor(account.provider == .gmail ? .red : .blue)
            VStack(alignment: .leading) {
                Text(account.email)
                    .font(.subheadline)
                Text(account.provider.rawValue.capitalized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Circle()
                .fill(account.status == .connected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Button("Disconnect") {
                onDisconnect()
            }
            .font(.caption)
            .foregroundColor(.red)
            .buttonStyle(.plain)
        }
    }
}
