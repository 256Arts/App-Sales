import Foundation
import CryptoKit
import KeychainAccess

/// A Google Analytics 4 property: one website's worth of traffic.
struct GoogleAnalyticsProperty: Codable, Hashable, Identifiable {
    /// `properties/123456789`, the form the Data API addresses it by.
    let id: String
    let name: String
    let accountName: String
}

/// Views of an app's page on the developer's website.
struct WebPageTraffic: Hashable {
    let views: Int
    let users: Int
}

enum GoogleAnalyticsError: LocalizedError {
    case notConnected
    /// Google refused the saved sign-in: revoked, expired, or the password changed.
    case signInExpired
    case google(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "Google Analytics is not connected."
        case .signInExpired:
            "Your Google sign-in has expired. Connect Google Analytics again."
        case .google(let message):
            message
        }
    }
}

/// The reader's Google Analytics connection: who signed in, which property is their website, and
/// which page on it is about each app — so the home screen can put web page views next to downloads.
///
/// Signing in is the app's job (it needs a browser session); everything after that is plain HTTP, so
/// this stays watchOS-clean. The connection is one per reader rather than per App Store Connect
/// account, and lives in the same iCloud-synchronized Keychain, so it follows them to every device.
@MainActor
@Observable
final class GoogleAnalytics {

    static let shared = GoogleAnalytics()

    /// The OAuth client, of Google Cloud's "iOS" type, which has no secret and redirects to a custom
    /// scheme. Empty hides the feature entirely, so a build without one never offers a broken sign-in.
    static let clientID = ""
    static var isAvailable: Bool { !clientID.isEmpty }

    private struct Connection: Codable {
        var refreshToken: String
        var property: GoogleAnalyticsProperty?
        /// Keyed by the app's Apple ID.
        var pageURLs: [String: URL] = [:]
    }

    private var connection: Connection? {
        didSet { persist() }
    }
    private var accessToken: (token: String, expires: Date)?

    var isConnected: Bool { connection != nil }
    var property: GoogleAnalyticsProperty? { connection?.property }
    var pageURLs: [String: URL] { connection?.pageURLs ?? [:] }

    private static let keychain = Keychain(service: "com.jaydenirwin.appsales")
        .synchronizable(true)
    private static let keychainKey = "google-analytics"

    private init() {
        // A screenshot run stays off the real Keychain, as `AccountManager` does.
        guard !ScreenshotMode.isActive,
              let data = try? Self.keychain.getData(Self.keychainKey) else { return }

        connection = try? JSONDecoder().decode(Connection.self, from: data)
    }

    private func persist() {
        guard !ScreenshotMode.isActive else { return }

        if let connection, let data = try? JSONEncoder().encode(connection) {
            try? Self.keychain.set(data, key: Self.keychainKey)
        } else {
            try? Self.keychain.remove(Self.keychainKey)
        }
    }

    func setProperty(_ property: GoogleAnalyticsProperty) {
        connection?.property = property
    }

    /// - Parameter url: `nil` forgets the app's page.
    func setPageURL(_ url: URL?, for appleID: String) {
        connection?.pageURLs[appleID] = url
    }

    func disconnect() {
        connection = nil
        accessToken = nil
    }

    // MARK: Sign In

    /// The custom scheme Google redirects an iOS-type client back to: its client ID, reversed.
    static var callbackScheme: String {
        "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }
    private static var redirectURI: String { callbackScheme + ":/oauthredirect" }

    /// The sign-in page to open, and the PKCE verifier to hand back to `connect(callback:verifier:)`.
    static func signInRequest() -> (url: URL, verifier: String) {
        let verifier = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }).base64URLEncoded
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/analytics.readonly"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return (components?.url ?? URL(filePath: "/"), verifier)
    }

    /// Finishes signing in with the URL the browser session was redirected to.
    func connect(callback: URL, verifier: String) async throws {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw GoogleAnalyticsError.google(items.first(where: { $0.name == "error" })?.value ?? "Google did not sign you in.")
        }

        let response = try await Self.token([
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": Self.redirectURI,
        ])
        guard let refreshToken = response.refreshToken else {
            throw GoogleAnalyticsError.google("Google did not grant offline access.")
        }

        accessToken = (response.accessToken, .now.addingTimeInterval(response.expiresIn - 60))
        connection = Connection(refreshToken: refreshToken)
        // Most people have one website; do not make them pick it.
        let properties = try await properties()
        if properties.count == 1, let property = properties.first {
            setProperty(property)
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: TimeInterval
        let refreshToken: String?
    }

    private static func token(_ parameters: [String: String]) async throws -> TokenResponse {
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
            return try decoder.decode(TokenResponse.self, from: data)
        }

        struct TokenError: Decodable { let error: String; let errorDescription: String? }
        let error = try? decoder.decode(TokenError.self, from: data)
        if error?.error == "invalid_grant" { throw GoogleAnalyticsError.signInExpired }
        throw GoogleAnalyticsError.google(error?.errorDescription ?? error?.error ?? "Google could not sign you in.")
    }

    private func validAccessToken() async throws -> String {
        if let accessToken, accessToken.expires > .now { return accessToken.token }
        guard let connection else { throw GoogleAnalyticsError.notConnected }

        do {
            let response = try await Self.token(["grant_type": "refresh_token", "refresh_token": connection.refreshToken])
            accessToken = (response.accessToken, .now.addingTimeInterval(response.expiresIn - 60))
            return response.accessToken
        } catch GoogleAnalyticsError.signInExpired {
            disconnect()
            throw GoogleAnalyticsError.signInExpired
        }
    }

    // MARK: Reading

    /// Every property the signed-in Google account can read, grouped the way Analytics lists them.
    func properties() async throws -> [GoogleAnalyticsProperty] {
        struct Page: Decodable {
            struct Account: Decodable {
                struct Property: Decodable { let property: String; let displayName: String }
                let displayName: String
                let propertySummaries: [Property]?
            }
            let accountSummaries: [Account]?
            let nextPageToken: String?
        }

        var properties: [GoogleAnalyticsProperty] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(string: "https://analyticsadmin.googleapis.com/v1beta/accountSummaries")
            components?.queryItems = [URLQueryItem(name: "pageSize", value: "200")]
            if let pageToken { components?.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken)) }

            let page: Page = try await send(URLRequest(url: components?.url ?? URL(filePath: "/")))
            for account in page.accountSummaries ?? [] {
                properties += (account.propertySummaries ?? []).map {
                    GoogleAnalyticsProperty(id: $0.property, name: $0.displayName, accountName: account.displayName)
                }
            }
            pageToken = page.nextPageToken
        } while pageToken?.isEmpty == false
        return properties
    }

    /// Each app's page traffic over the last 30 days, the window the home screen counts downloads in.
    /// Apps without a page are left out.
    func traffic() async throws -> [String: WebPageTraffic] {
        guard let property else { throw GoogleAnalyticsError.notConnected }

        return try await withThrowingTaskGroup(of: (String, WebPageTraffic).self) { group in
            for (appleID, url) in pageURLs {
                group.addTask { (appleID, try await self.traffic(of: url, in: property)) }
            }
            return try await group.reduce(into: [:]) { $0[$1.0] = $1.1 }
        }
    }

    private func traffic(of url: URL, in property: GoogleAnalyticsProperty) async throws -> WebPageTraffic {
        struct Report: Decodable {
            struct Row: Decodable {
                struct Value: Decodable { let value: String }
                let metricValues: [Value]
            }
            let rows: [Row]?
        }

        // The same page is often reachable with and without `www.` and a trailing slash.
        let host = (url.host() ?? "").replacing(/^www\./, with: "")
        let path = url.path().isEmpty ? "/" : url.path()
        let paths = path == "/" ? [path] : [path.hasSuffix("/") ? String(path.dropLast()) : path, path.hasSuffix("/") ? path : path + "/"]
        let body: [String: Any] = [
            "dateRanges": [["startDate": "30daysAgo", "endDate": "today"]],
            // No dimensions, so Google counts each user once across the page's variants.
            "metrics": [["name": "screenPageViews"], ["name": "totalUsers"]],
            "dimensionFilter": ["andGroup": ["expressions": [
                ["filter": ["fieldName": "hostName", "inListFilter": ["values": [host, "www." + host]]]],
                ["filter": ["fieldName": "pagePath", "inListFilter": ["values": paths]]],
            ]]],
        ]

        var request = URLRequest(url: URL(string: "https://analyticsdata.googleapis.com/v1beta/\(property.id):runReport") ?? URL(filePath: "/"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let report: Report = try await send(request)
        let values = report.rows?.first?.metricValues.map { Int($0.value) ?? 0 } ?? []
        return WebPageTraffic(views: values.first ?? 0, users: values.dropFirst().first ?? 0)
    }

    private struct ErrorResponse: Decodable {
        struct Body: Decodable { let message: String }
        let error: Body
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        var request = request
        request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 200 {
            return try JSONDecoder().decode(T.self, from: data)
        }

        if (response as? HTTPURLResponse)?.statusCode == 401 {
            accessToken = nil
        }
        throw GoogleAnalyticsError.google((try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message ?? "Google Analytics could not be reached.")
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
