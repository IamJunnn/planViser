import Foundation
import AppAuth

final class GmailAuthService: ObservableObject {
    static let shared = GmailAuthService()

    @Published var isAuthenticated = false
    @Published var userEmail: String?
    @Published var userName: String?

    private var currentAuthorizationFlow: OIDExternalUserAgentSession?

    private let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    private let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    private let userInfoEndpoint = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!

    private let scopes = [
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/calendar"
    ]

    private init() {
        // Check if we already have tokens
        if let _ = try? KeychainService.shared.getAccessToken(for: "gmail") {
            isAuthenticated = true
            fetchUserProfile()
        }
    }

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
            additionalParameters: nil
        )

        currentAuthorizationFlow = OIDAuthState.authState(
            byPresenting: request,
            callback: { [weak self] authState, error in
                guard let self = self else { return }

                if let authState = authState {
                    if let accessToken = authState.lastTokenResponse?.accessToken {
                        try? KeychainService.shared.saveAccessToken(accessToken, for: "gmail")
                    }
                    if let refreshToken = authState.lastTokenResponse?.refreshToken {
                        try? KeychainService.shared.saveRefreshToken(refreshToken, for: "gmail")
                    }

                    DispatchQueue.main.async {
                        self.isAuthenticated = true
                        self.fetchUserProfile()
                    }
                } else if let error = error {
                    print("Gmail auth error: \(error.localizedDescription)")
                }
            }
        )
    }

    func signOut() {
        try? KeychainService.shared.deleteTokens(for: "gmail")
        DispatchQueue.main.async {
            self.isAuthenticated = false
            self.userEmail = nil
            self.userName = nil
        }
    }

    func getValidAccessToken(completion: @escaping (String?) -> Void) {
        guard let accessToken = try? KeychainService.shared.getAccessToken(for: "gmail") else {
            completion(nil)
            return
        }
        // For now, return the stored token directly.
        // A production app would check expiry and use the refresh token.
        completion(accessToken)
    }

    func refreshAccessToken(completion: @escaping (String?) -> Void) {
        guard let refreshToken = try? KeychainService.shared.getRefreshToken(for: "gmail") else {
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
                try? KeychainService.shared.saveAccessToken(token, for: "gmail")
                if let newRefresh = response?.refreshToken {
                    try? KeychainService.shared.saveRefreshToken(newRefresh, for: "gmail")
                }
                completion(token)
            } else {
                print("Gmail token refresh failed: \(error?.localizedDescription ?? "unknown")")
                self?.signOut()
                completion(nil)
            }
        }
    }

    private func fetchUserProfile() {
        getValidAccessToken { [weak self] token in
            guard let token = token else { return }

            var request = URLRequest(url: self!.userInfoEndpoint)
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { data, _, error in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }

                DispatchQueue.main.async {
                    self?.userEmail = json["email"] as? String
                    self?.userName = json["name"] as? String
                }
            }.resume()
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
}
