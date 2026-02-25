import SwiftUI

struct IMAPSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var displayName = ""
    @State private var imapServer = ""
    @State private var portString = "993"
    @State private var password = ""

    @State private var isTesting = false
    @State private var testSucceeded = false
    @State private var testError: String?
    @State private var isConnecting = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Connect IMAP / Exchange")
                    .scaledFont(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Account") {
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress)
                        .onChange(of: email) { _, newValue in
                            autoDetectServer(from: newValue)
                            testSucceeded = false
                        }
                    TextField("Display name (optional)", text: $displayName)
                }

                Section("Server") {
                    TextField("IMAP server", text: $imapServer)
                        .onChange(of: imapServer) { _, _ in testSucceeded = false }
                    TextField("Port", text: $portString)
                        .frame(width: 80)
                        .onChange(of: portString) { _, _ in testSucceeded = false }
                }

                Section("Authentication") {
                    SecureField("Password", text: $password)
                        .onChange(of: password) { _, _ in testSucceeded = false }

                    Text("For Gmail or accounts with 2FA, use an app-specific password.")
                        .scaledFont(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    HStack(spacing: 12) {
                        // Test Connection
                        Button {
                            testConnection()
                        } label: {
                            HStack(spacing: 4) {
                                if isTesting {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(isTesting ? "Testing..." : "Test Connection")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!canTest || isTesting)

                        if testSucceeded {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .scaledFont(.caption)
                        }

                        Spacer()

                        // Connect
                        Button("Connect") {
                            connectAccount()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!testSucceeded || isConnecting)
                    }

                    if let error = testError {
                        Text(error)
                            .scaledFont(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 450, height: 420)
    }

    // MARK: - Validation

    private var canTest: Bool {
        !email.isEmpty && !imapServer.isEmpty && !password.isEmpty && !portString.isEmpty
    }

    // MARK: - Auto-detect Server

    private func autoDetectServer(from email: String) {
        guard let atIndex = email.firstIndex(of: "@") else { return }
        let domain = String(email[email.index(after: atIndex)...]).lowercased()
        guard !domain.isEmpty else { return }

        // Well-known IMAP servers
        let knownServers: [String: String] = [
            "gmail.com": "imap.gmail.com",
            "googlemail.com": "imap.gmail.com",
            "outlook.com": "outlook.office365.com",
            "hotmail.com": "outlook.office365.com",
            "live.com": "outlook.office365.com",
            "yahoo.com": "imap.mail.yahoo.com",
            "icloud.com": "imap.mail.me.com",
            "me.com": "imap.mail.me.com",
            "mac.com": "imap.mail.me.com",
            "aol.com": "imap.aol.com"
        ]

        if let known = knownServers[domain] {
            imapServer = known
        } else {
            imapServer = "imap.\(domain)"
        }
        portString = "993"
    }

    // MARK: - Test Connection

    private func testConnection() {
        guard let port = UInt16(portString) else {
            testError = "Invalid port number"
            return
        }

        isTesting = true
        testError = nil
        testSucceeded = false

        IMAPAPIService.shared.testConnection(
            host: imapServer,
            port: port,
            email: email,
            password: password
        ) { result in
            DispatchQueue.main.async {
                isTesting = false
                switch result {
                case .success:
                    testSucceeded = true
                    testError = nil
                case .failure(let error):
                    testSucceeded = false
                    testError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Connect Account

    private func connectAccount() {
        guard let port = UInt16(portString) else { return }

        isConnecting = true
        let name = displayName.isEmpty ? email : displayName

        IMAPAuthService.shared.addAccount(
            email: email,
            displayName: name,
            host: imapServer,
            port: port,
            password: password
        )

        isConnecting = false
        dismiss()
    }
}
