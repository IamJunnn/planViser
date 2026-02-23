import Foundation
import MSAL

final class OutlookAuthService: ObservableObject {
    static let shared = OutlookAuthService()

    @Published var isAuthenticated = false
    @Published var userEmail: String?
    @Published var userName: String?

    private var msalApplication: MSALPublicClientApplication?
    private var currentAccount: MSALAccount?

    private let scopes = [
        "Mail.Read",
        "Calendars.ReadWrite",
        "User.Read"
    ]

    private init() {
        setupMSAL()
        loadExistingAccount()
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

    private func loadExistingAccount() {
        guard let app = msalApplication else { return }

        do {
            let accounts = try app.allAccounts()
            if let account = accounts.first {
                currentAccount = account
                DispatchQueue.main.async {
                    self.isAuthenticated = true
                    self.userEmail = account.username
                    self.userName = account.username
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
                self.currentAccount = result.account
                try? KeychainService.shared.saveAccessToken(result.accessToken, for: "outlook")

                DispatchQueue.main.async {
                    self.isAuthenticated = true
                    self.userEmail = result.account.username
                    self.userName = result.account.username
                }
            } else if let error = error {
                print("Outlook auth error: \(error.localizedDescription)")
            }
        }
    }

    func signOut() {
        guard let app = msalApplication, let account = currentAccount else { return }

        do {
            try app.remove(account)
        } catch {
            print("MSAL sign out error: \(error)")
        }

        try? KeychainService.shared.deleteTokens(for: "outlook")
        currentAccount = nil

        DispatchQueue.main.async {
            self.isAuthenticated = false
            self.userEmail = nil
            self.userName = nil
        }
    }

    func getValidAccessToken(completion: @escaping (String?) -> Void) {
        guard let app = msalApplication, let account = currentAccount else {
            completion(nil)
            return
        }

        let silentParams = MSALSilentTokenParameters(scopes: scopes, account: account)

        app.acquireTokenSilent(with: silentParams) { [weak self] result, error in
            if let result = result {
                try? KeychainService.shared.saveAccessToken(result.accessToken, for: "outlook")
                completion(result.accessToken)
            } else if let nsError = error as? NSError,
                      nsError.domain == MSALErrorDomain,
                      nsError.code == MSALError.interactionRequired.rawValue {
                // Token expired, need interactive sign-in
                DispatchQueue.main.async {
                    self?.isAuthenticated = false
                }
                completion(nil)
            } else {
                completion(nil)
            }
        }
    }
}
