import Foundation

struct IMAPAccountInfo: Equatable, Identifiable {
    let email: String
    let displayName: String
    let host: String
    let port: UInt16
    var id: String { email }
}

final class IMAPAuthService: ObservableObject {
    static let shared = IMAPAuthService()

    @Published var connectedAccounts: [IMAPAccountInfo] = []

    var hasConnectedAccounts: Bool { !connectedAccounts.isEmpty }

    /// Keychain key that stores the comma-separated list of connected emails
    private let accountEmailsKey = "imap.accountEmails"

    private init() {
        loadConnectedAccounts()
    }

    // MARK: - Add Account

    func addAccount(email: String, displayName: String, host: String, port: UInt16, password: String) {
        // Save credentials to Keychain
        try? KeychainService.shared.save(password, forKey: "imap.\(email).password")
        try? KeychainService.shared.save(host, forKey: "imap.\(email).host")
        try? KeychainService.shared.save(String(port), forKey: "imap.\(email).port")

        // Add to connected emails list
        addConnectedEmail(email)

        DispatchQueue.main.async {
            let info = IMAPAccountInfo(email: email, displayName: displayName, host: host, port: port)
            if !self.connectedAccounts.contains(where: { $0.email == email }) {
                self.connectedAccounts.append(info)
            }
        }
    }

    // MARK: - Sign Out

    func signOut(email: String) {
        try? KeychainService.shared.delete(forKey: "imap.\(email).password")
        try? KeychainService.shared.delete(forKey: "imap.\(email).host")
        try? KeychainService.shared.delete(forKey: "imap.\(email).port")
        removeConnectedEmail(email)

        IMAPAPIService.shared.disconnect(email: email)

        DispatchQueue.main.async {
            self.connectedAccounts.removeAll { $0.email == email }
        }
    }

    // MARK: - Get Credentials

    func getCredentials(for email: String) -> (host: String, port: UInt16, password: String)? {
        guard let password = try? KeychainService.shared.get(forKey: "imap.\(email).password"),
              let host = try? KeychainService.shared.get(forKey: "imap.\(email).host"),
              let portStr = try? KeychainService.shared.get(forKey: "imap.\(email).port"),
              let port = UInt16(portStr) else {
            return nil
        }
        return (host, port, password)
    }

    // MARK: - Load Accounts

    private func loadConnectedAccounts() {
        guard let emailsString = try? KeychainService.shared.get(forKey: accountEmailsKey),
              !emailsString.isEmpty else {
            return
        }

        let emailList = emailsString.components(separatedBy: ",")
        var validAccounts: [IMAPAccountInfo] = []

        for email in emailList {
            if let creds = getCredentials(for: email) {
                validAccounts.append(IMAPAccountInfo(
                    email: email,
                    displayName: email,
                    host: creds.host,
                    port: creds.port
                ))
            }
        }

        connectedAccounts = validAccounts
    }

    // MARK: - Email List Management

    private func addConnectedEmail(_ email: String) {
        var emails = getStoredEmails()
        if !emails.contains(email) {
            emails.append(email)
            try? KeychainService.shared.save(emails.joined(separator: ","), forKey: accountEmailsKey)
        }
    }

    private func removeConnectedEmail(_ email: String) {
        var emails = getStoredEmails()
        emails.removeAll { $0 == email }
        if emails.isEmpty {
            try? KeychainService.shared.delete(forKey: accountEmailsKey)
        } else {
            try? KeychainService.shared.save(emails.joined(separator: ","), forKey: accountEmailsKey)
        }
    }

    private func getStoredEmails() -> [String] {
        guard let emailsString = try? KeychainService.shared.get(forKey: accountEmailsKey),
              !emailsString.isEmpty else {
            return []
        }
        return emailsString.components(separatedBy: ",")
    }
}
