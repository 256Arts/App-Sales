import Foundation
import CryptoKit

enum GoogleSignInError: LocalizedError {
    case notConnected(service: String)
    /// Google refused the saved sign-in: revoked, expired, or the password changed.
    case signInExpired(service: String)
    case google(String)

    var errorDescription: String? {
        switch self {
        case .notConnected(let service):
            String(localized: "You are not signed in to \(service).")
        case .signInExpired(let service):
            String(localized: "Your Google sign-in has expired. Sign in to \(service) again.")
        case .google(let message):
            message
        }
    }
}

/// One Google identity signed in to one service. A reader can have several — a work account managed
/// by their employer beside a personal one — so each service keeps a list of them.
struct GoogleAccount: Codable, Hashable, Identifiable {
    /// Google's stable user ID (`sub`), so signing in again replaces rather than duplicates.
    let id: String
    let email: String
    var refreshToken: String
}

/// The OAuth plumbing every Google service App Sales reads shares: one client, a PKCE sign-in per
/// scope, and the token endpoint. Each service keeps its own refresh tokens, so signing in to one
/// never asks for another's permission and signing out of one leaves the other alone.
enum GoogleSignIn {

    /// The OAuth client, of Google Cloud's "iOS" type, which has no secret and redirects to a custom
    /// scheme. Empty hides every Google service, so a build without one never offers a broken sign-in.
    static let clientID = "1019038999237-h5sj3hoc6v80214172tkemuqvkhkcfnb.apps.googleusercontent.com"
    static var isAvailable: Bool { !clientID.isEmpty }

    /// The custom scheme Google redirects an iOS-type client back to: its client ID, reversed.
    static var callbackScheme: String {
        "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }
    private static var redirectURI: String { callbackScheme + ":/oauthredirect" }

    /// The sign-in page to open, and the PKCE verifier to hand back to `finish(callback:verifier:)`.
    static func request(scope: String) -> (url: URL, verifier: String) {
        let verifier = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }).base64URLEncoded
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            // `openid email` names the account, so several sign-ins can be told apart.
            URLQueryItem(name: "scope", value: "openid email " + scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return (components?.url ?? URL(filePath: "/"), verifier)
    }

    struct Token {
        let accessToken: String
        let expires: Date
        let refreshToken: String?
        let idToken: String?
    }

    /// Trades the URL the browser session was redirected to for a token that can refresh itself.
    static func finish(callback: URL, verifier: String) async throws -> (token: Token, account: GoogleAccount) {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw GoogleSignInError.google(items.first(where: { $0.name == "error" })?.value ?? "Google did not sign you in.")
        }

        let token = try await token([
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI,
        ], service: "Google")
        guard let refreshToken = token.refreshToken else {
            throw GoogleSignInError.google("Google did not grant offline access.")
        }
        guard let identity = token.idToken.flatMap({ Identity(idToken: $0) }) else {
            throw GoogleSignInError.google("Google did not say who signed in.")
        }
        return (token, GoogleAccount(id: identity.sub, email: identity.email ?? identity.sub, refreshToken: refreshToken))
    }

    /// The claims of an ID token. It came straight from Google's token endpoint over TLS, so its
    /// signature is not checked.
    private struct Identity: Decodable {
        let sub: String
        let email: String?

        init?(idToken: String) {
            let parts = idToken.split(separator: ".")
            guard parts.count == 3 else { return nil }

            var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            guard let data = Data(base64Encoded: payload),
                  let identity = try? JSONDecoder().decode(Self.self, from: data) else { return nil }

            self = identity
        }
    }

    static func refresh(_ refreshToken: String, service: String) async throws -> Token {
        try await token(["grant_type": "refresh_token", "refresh_token": refreshToken], service: service)
    }

    private static func token(_ parameters: [String: String], service: String) async throws -> Token {
        struct Response: Decodable {
            let accessToken: String
            let expiresIn: TimeInterval
            let refreshToken: String?
            let idToken: String?
        }

        var components = URLComponents()
        components.queryItems = (parameters.merging(["client_id": clientID]) { $1 })
            .map { URLQueryItem(name: $0.key, value: $0.value) }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token") ?? URL(filePath: "/"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Form encoding reads a bare `+` as a space.
        request.httpBody = Data((components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if (response as? HTTPURLResponse)?.statusCode == 200 {
            let response = try decoder.decode(Response.self, from: data)
            return Token(accessToken: response.accessToken, expires: .now.addingTimeInterval(response.expiresIn - 60), refreshToken: response.refreshToken, idToken: response.idToken)
        }

        struct TokenError: Decodable { let error: String; let errorDescription: String? }
        let error = try? decoder.decode(TokenError.self, from: data)
        if error?.error == "invalid_grant" { throw GoogleSignInError.signInExpired(service: service) }
        throw GoogleSignInError.google(error?.errorDescription ?? error?.error ?? String(localized: "Google could not sign you in."))
    }

    private struct ErrorResponse: Decodable {
        struct Body: Decodable { let message: String }
        let error: Body
    }

    /// Sends an authorized request and decodes a 200's body. `invalidate` is called on a 401, so the
    /// caller drops an access token Google no longer accepts.
    static func send<T: Decodable>(_ request: URLRequest, accessToken: String, service: String, invalidate: () -> Void) async throws -> T {
        var request = request
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 200 {
            return try JSONDecoder().decode(T.self, from: data)
        }

        if (response as? HTTPURLResponse)?.statusCode == 401 {
            invalidate()
        }
        throw GoogleSignInError.google((try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message ?? String(localized: "\(service) could not be reached."))
    }
}

/// A service's access tokens, one per signed-in account, held in memory only since each lasts an hour.
@MainActor
final class GoogleAccessTokens {

    private let service: String
    private var tokens: [GoogleAccount.ID: GoogleSignIn.Token] = [:]

    init(service: String) {
        self.service = service
    }

    func store(_ token: GoogleSignIn.Token, for account: GoogleAccount) {
        tokens[account.id] = token
    }

    func remove(_ account: GoogleAccount) {
        tokens[account.id] = nil
    }

    /// Throws `signInExpired` when Google refuses the account's refresh token, for the caller to sign it out.
    func send<T: Decodable>(_ request: URLRequest, as account: GoogleAccount) async throws -> T {
        try await GoogleSignIn.send(request, accessToken: try await accessToken(for: account), service: service) { tokens[account.id] = nil }
    }

    private func accessToken(for account: GoogleAccount) async throws -> String {
        if let token = tokens[account.id], token.expires > .now { return token.accessToken }

        let token = try await GoogleSignIn.refresh(account.refreshToken, service: service)
        tokens[account.id] = token
        return token.accessToken
    }
}

extension Data {
    /// Base64 without padding, and URL-safe, as PKCE requires.
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
