import Foundation
import MSAL

struct OutlookAccountInfo: Equatable, Identifiable {
    let email: String
    let displayName: String
    var id: String { email }
}

final class OutlookAuthService: ObservableObject {
    static let shared = OutlookAuthService()

    @Published var connectedAccounts: [OutlookAccountInfo] = []

    var hasConnectedAccounts: Bool { !connectedAccounts.isEmpty }

    private var msalApplication: MSALPublicClientApplication?

    /// Cache of email → MSALAccount for token operations
    private var msalAccountMap: [String: MSALAccount] = [:]

    private let scopes = [
        "Mail.Read",
        "Calendars.ReadWrite",
        "User.Read"
    ]

    private init() {
        setupMSAL()
        loadExistingAccounts()
    }

    private func setupMSAL() {
        guard let clientID = Optional(Secrets.microsoftClientID),
              clientID != "YOUR_MICROSOFT_CLIENT_ID" else {
            print("Outlook: No client ID configured")
            return
        }

        do {
            let redirectURI = Secrets.microsoftRedirectURI
            let config = MSALPublicClientApplicationConfig(
                clientId: clientID,
                redirectUri: redirectURI,
                authority: try MSALAADAuthority(
                    url: URL(string: "https://login.microsoftonline.com/common")!
                )
            )
            msalApplication = try MSALPublicClientApplication(configuration: config)
        } catch {
            print("MSAL setup error: \(error.localizedDescription)")
        }
    }

    private func loadExistingAccounts() {
        guard let app = msalApplication else { return }

        do {
            let accounts = try app.allAccounts()
            var loaded: [OutlookAccountInfo] = []

            for account in accounts {
                guard let email = account.username else { continue }
                msalAccountMap[email] = account
                loaded.append(OutlookAccountInfo(email: email, displayName: email))
            }

            if !loaded.isEmpty {
                DispatchQueue.main.async {
                    self.connectedAccounts = loaded
                }
            }
        } catch {
            print("Failed to load MSAL accounts: \(error)")
        }
    }

    func signIn() {
        guard let app = msalApplication else {
            print("MSAL not configured")
            return
        }

        let parameters = MSALInteractiveTokenParameters(scopes: scopes)

        app.acquireToken(with: parameters) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let email = result.account.username ?? "unknown"
                self.msalAccountMap[email] = result.account
                try? KeychainService.shared.saveAccessToken(result.accessToken, for: "outlook.\(email)")

                DispatchQueue.main.async {
                    let info = OutlookAccountInfo(email: email, displayName: email)
                    if !self.connectedAccounts.contains(where: { $0.email == email }) {
                        self.connectedAccounts.append(info)
                    }
                }
            } else if let error = error {
                print("Outlook auth error: \(error.localizedDescription)")
            }
        }
    }

    func signOut(email: String) {
        guard let app = msalApplication,
              let msalAccount = msalAccountMap[email] else { return }

        do {
            try app.remove(msalAccount)
        } catch {
            print("MSAL sign out error: \(error)")
        }

        msalAccountMap.removeValue(forKey: email)
        try? KeychainService.shared.deleteTokens(for: "outlook.\(email)")

        DispatchQueue.main.async {
            self.connectedAccounts.removeAll { $0.email == email }
        }
    }

    func getValidAccessToken(for email: String, completion: @escaping (String?) -> Void) {
        guard let app = msalApplication,
              let msalAccount = msalAccountMap[email] else {
            completion(nil)
            return
        }

        let silentParams = MSALSilentTokenParameters(scopes: scopes, account: msalAccount)

        app.acquireTokenSilent(with: silentParams) { result, error in
            if let result = result {
                try? KeychainService.shared.saveAccessToken(result.accessToken, for: "outlook.\(email)")
                completion(result.accessToken)
            } else if let nsError = error as? NSError,
                      nsError.domain == MSALErrorDomain,
                      nsError.code == MSALError.interactionRequired.rawValue {
                completion(nil)
            } else {
                completion(nil)
            }
        }
    }
}
