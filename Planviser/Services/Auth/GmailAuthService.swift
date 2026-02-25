import Foundation
import AppAuth

struct GmailAccountInfo: Equatable, Identifiable {
    let email: String
    let displayName: String
    var id: String { email }
}

final class GmailAuthService: ObservableObject {
    static let shared = GmailAuthService()

    @Published var connectedAccounts: [GmailAccountInfo] = []

    /// Convenience for checking if any Gmail accounts are connected
    var hasConnectedAccounts: Bool { !connectedAccounts.isEmpty }

    private var currentAuthorizationFlow: OIDExternalUserAgentSession?

    private let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    private let userInfoEndpoint = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!

    private let scopes = [
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/calendar"
    ]

    /// Keychain key that stores the comma-separated list of connected emails
    private let accountEmailsKey = "gmail.accountEmails"

    private init() {
        migrateFromLegacyKeys()
        loadConnectedAccounts()
    }

    // MARK: - Sign In

    func signIn() {
        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: authorizationEndpoint,
            tokenEndpoint: tokenEndpoint
        )

        let redirectURI = URL(string: Secrets.googleRedirectURI)!

        let request = OIDAuthorizationRequest(
            configuration: configuration,
            clientId: Secrets.googleClientID,
            clientSecret: nil,
            scopes: scopes,
            redirectURL: redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: ["prompt": "select_account"]
        )

        currentAuthorizationFlow = OIDAuthState.authState(
            byPresenting: request,
            callback: { [weak self] authState, error in
                guard let self = self else { return }

                if let authState = authState,
                   let accessToken = authState.lastTokenResponse?.accessToken {
                    // We have tokens — fetch the user profile to get the email,
                    // then store tokens under the per-account key.
                    self.fetchUserProfile(accessToken: accessToken) { email, displayName in
                        guard let email = email else { return }

                        // Save tokens keyed by email
                        try? KeychainService.shared.saveAccessToken(accessToken, for: "gmail.\(email)")
                        if let refreshToken = authState.lastTokenResponse?.refreshToken {
                            try? KeychainService.shared.saveRefreshToken(refreshToken, for: "gmail.\(email)")
                        }

                        // Add to connected accounts list
                        self.addConnectedEmail(email)

                        DispatchQueue.main.async {
                            let info = GmailAccountInfo(email: email, displayName: displayName ?? email)
                            if !self.connectedAccounts.contains(where: { $0.email == email }) {
                                self.connectedAccounts.append(info)
                            }
                        }
                    }
                } else if let error = error {
                    print("Gmail auth error: \(error.localizedDescription)")
                }
            }
        )
    }

    // MARK: - Sign Out (specific account)

    func signOut(email: String) {
        try? KeychainService.shared.deleteTokens(for: "gmail.\(email)")
        removeConnectedEmail(email)

        DispatchQueue.main.async {
            self.connectedAccounts.removeAll { $0.email == email }
        }
    }

    // MARK: - Token Access (per account)

    func getValidAccessToken(for email: String, completion: @escaping (String?) -> Void) {
        guard let accessToken = try? KeychainService.shared.getAccessToken(for: "gmail.\(email)") else {
            completion(nil)
            return
        }
        completion(accessToken)
    }

    func refreshAccessToken(for email: String, completion: @escaping (String?) -> Void) {
        guard let refreshToken = try? KeychainService.shared.getRefreshToken(for: "gmail.\(email)") else {
            completion(nil)
            return
        }

        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: authorizationEndpoint,
            tokenEndpoint: tokenEndpoint
        )

        let tokenRequest = OIDTokenRequest(
            configuration: configuration,
            grantType: OIDGrantTypeRefreshToken,
            authorizationCode: nil,
            redirectURL: URL(string: Secrets.googleRedirectURI)!,
            clientID: Secrets.googleClientID,
            clientSecret: nil,
            scope: nil,
            refreshToken: refreshToken,
            codeVerifier: nil,
            additionalParameters: nil
        )

        OIDAuthorizationService.perform(tokenRequest) { [weak self] response, error in
            if let token = response?.accessToken {
                try? KeychainService.shared.saveAccessToken(token, for: "gmail.\(email)")
                if let newRefresh = response?.refreshToken {
                    try? KeychainService.shared.saveRefreshToken(newRefresh, for: "gmail.\(email)")
                }
                completion(token)
            } else {
                print("Gmail token refresh failed for \(email): \(error?.localizedDescription ?? "unknown")")
                self?.signOut(email: email)
                completion(nil)
            }
        }
    }

    // MARK: - Handle OAuth redirect

    func handleRedirect(url: URL) -> Bool {
        if let flow = currentAuthorizationFlow, flow.resumeExternalUserAgentFlow(with: url) {
            currentAuthorizationFlow = nil
            return true
        }
        return false
    }

    // MARK: - Private Helpers

    private func fetchUserProfile(accessToken: String, completion: @escaping (String?, String?) -> Void) {
        var request = URLRequest(url: userInfoEndpoint)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil, nil)
                return
            }

            let email = json["email"] as? String
            let name = json["name"] as? String
            completion(email, name)
        }.resume()
    }

    /// Load the list of connected accounts from Keychain and verify each has tokens
    private func loadConnectedAccounts() {
        guard let emailsString = try? KeychainService.shared.get(forKey: accountEmailsKey),
              !emailsString.isEmpty else {
            return
        }

        let emails = emailsString.components(separatedBy: ",")
        var validAccounts: [GmailAccountInfo] = []

        for email in emails {
            if let _ = try? KeychainService.shared.getAccessToken(for: "gmail.\(email)") {
                validAccounts.append(GmailAccountInfo(email: email, displayName: email))
                // Fetch display name in background
                getValidAccessToken(for: email) { [weak self] token in
                    guard let token = token else { return }
                    self?.fetchUserProfile(accessToken: token) { _, displayName in
                        guard let displayName = displayName else { return }
                        DispatchQueue.main.async {
                            if let idx = self?.connectedAccounts.firstIndex(where: { $0.email == email }) {
                                self?.connectedAccounts[idx] = GmailAccountInfo(email: email, displayName: displayName)
                            }
                        }
                    }
                }
            }
        }

        connectedAccounts = validAccounts
    }

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

    // MARK: - Migration from legacy single-account keys

    /// Migrate from old "gmail" keychain keys to new "gmail.<email>" format
    private func migrateFromLegacyKeys() {
        // Check if legacy tokens exist
        guard let legacyAccessToken = try? KeychainService.shared.getAccessToken(for: "gmail") else {
            return
        }

        // Already migrated if we have accountEmails
        if let existing = try? KeychainService.shared.get(forKey: accountEmailsKey), !existing.isEmpty {
            // Clean up legacy keys
            try? KeychainService.shared.deleteTokens(for: "gmail")
            return
        }

        // Fetch the email for this legacy token so we can key it properly
        var request = URLRequest(url: userInfoEndpoint)
        request.addValue("Bearer \(legacyAccessToken)", forHTTPHeaderField: "Authorization")

        // Use a semaphore since this runs during init
        let semaphore = DispatchSemaphore(value: 0)
        var migratedEmail: String?

        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let email = json["email"] as? String {
                migratedEmail = email
            }
            semaphore.signal()
        }.resume()

        // Wait briefly — if network fails, migration will retry next launch
        _ = semaphore.wait(timeout: .now() + 5)

        if let email = migratedEmail {
            // Copy tokens to new per-account keys
            try? KeychainService.shared.saveAccessToken(legacyAccessToken, for: "gmail.\(email)")
            if let refreshToken = try? KeychainService.shared.getRefreshToken(for: "gmail") {
                try? KeychainService.shared.saveRefreshToken(refreshToken, for: "gmail.\(email)")
            }
            try? KeychainService.shared.save(email, forKey: accountEmailsKey)
            // Remove legacy keys
            try? KeychainService.shared.deleteTokens(for: "gmail")
        }
    }
}
