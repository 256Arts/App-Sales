import Foundation
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
    /// The page counted: the one the reader set, or the one found by the app's name.
    let url: URL
    let views: Int
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

    private static let service = "Google Analytics"

    private struct Connection: Codable {
        var refreshToken: String
        var property: GoogleAnalyticsProperty?
        /// Keyed by the app's Apple ID.
        var pageURLs: [String: URL] = [:]
    }

    private var connection: Connection? {
        didSet { persist() }
    }
    private var accessToken: GoogleSignIn.Token?

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

    static func signInRequest() -> (url: URL, verifier: String) {
        GoogleSignIn.request(scope: "https://www.googleapis.com/auth/analytics.readonly")
    }

    /// Finishes signing in with the URL the browser session was redirected to.
    func connect(callback: URL, verifier: String) async throws {
        let (token, refreshToken) = try await GoogleSignIn.finish(callback: callback, verifier: verifier)
        accessToken = token
        connection = Connection(refreshToken: refreshToken)
        // Most people have one website; do not make them pick it.
        let properties = try await properties()
        if properties.count == 1, let property = properties.first {
            setProperty(property)
        }
    }

    private func validAccessToken() async throws -> String {
        if let accessToken, accessToken.expires > .now { return accessToken.accessToken }
        guard let connection else { throw GoogleSignInError.notConnected(service: Self.service) }

        do {
            let token = try await GoogleSignIn.refresh(connection.refreshToken, service: Self.service)
            accessToken = token
            return token.accessToken
        } catch GoogleSignInError.signInExpired {
            disconnect()
            throw GoogleSignInError.signInExpired(service: Self.service)
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

    /// Each app's page traffic over the last 30 days, the window the home screen counts downloads in,
    /// keyed by Apple ID. An app's page is the one the reader set or, failing that, any page whose last
    /// path component spells the app's name — `256arts.com/spritepencil` for Sprite Pencil. Apps with
    /// no page are left out.
    func traffic(for apps: [(appleID: String, name: String)]) async throws -> [String: WebPageTraffic] {
        guard let property else { throw GoogleSignInError.notConnected(service: Self.service) }

        struct Report: Decodable {
            struct Row: Decodable {
                struct Value: Decodable { let value: String }
                let dimensionValues: [Value]
                let metricValues: [Value]
            }
            let rows: [Row]?
        }

        // One report of every page, rather than one per app, so matching by name costs nothing extra.
        let body: [String: Any] = [
            "dateRanges": [["startDate": "30daysAgo", "endDate": "today"]],
            "dimensions": [["name": "hostName"], ["name": "pagePath"]],
            "metrics": [["name": "screenPageViews"]],
            "limit": 10_000,
        ]

        var request = URLRequest(url: URL(string: "https://analyticsdata.googleapis.com/v1beta/\(property.id):runReport") ?? URL(filePath: "/"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let report: Report = try await send(request)

        // The same page is often reachable with and without `www.` and a trailing slash; those count together.
        var pages: [WebPage: Int] = [:]
        for row in report.rows ?? [] {
            guard row.dimensionValues.count == 2 else { continue }
            let page = WebPage(host: row.dimensionValues[0].value, path: row.dimensionValues[1].value)
            pages[page, default: 0] += Int(row.metricValues.first?.value ?? "") ?? 0
        }

        var traffic: [String: WebPageTraffic] = [:]
        for app in apps {
            if let url = pageURLs[app.appleID] {
                traffic[app.appleID] = WebPageTraffic(url: url, views: pages[WebPage(url)] ?? 0)
            } else if let match = Self.page(named: app.name, in: pages) {
                traffic[app.appleID] = WebPageTraffic(url: match.page.url, views: match.views)
            }
        }
        return traffic
    }

    /// The most viewed page whose last path component is the app's name, with or without its
    /// App Store subtitle ("Sprite Pencil: Pixel Art" is `spritepencil`).
    private static func page(named name: String, in pages: [WebPage: Int]) -> (page: WebPage, views: Int)? {
        let full = WebPage.slug(name)
        let short = WebPage.slug(String(name.prefix { !":–—|".contains($0) }).replacing(#/ - .*/#, with: ""))
        return pages
            .filter { !$0.key.lastComponent.isEmpty && [full, short].contains($0.key.lastComponent) }
            .max { $0.value < $1.value }
            .map { ($0.key, $0.value) }
    }

    /// A page with the variants Google counts apart folded together: `www.`, the trailing slash, and letter case.
    private struct WebPage: Hashable {
        let host: String
        let path: String

        init(host: String, path: String) {
            self.host = host.lowercased().replacing(/^www\./, with: "")
            let path = path.lowercased().split(separator: "?").first.map(String.init) ?? ""
            self.path = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : (path.isEmpty ? "/" : path)
        }

        init(_ url: URL) {
            self.init(host: url.host() ?? "", path: url.path())
        }

        var url: URL {
            URL(string: "https://" + host + path) ?? URL(filePath: "/")
        }

        var lastComponent: String {
            Self.slug(path.split(separator: "/").last.map(String.init) ?? "")
        }

        /// Letters and digits only, so "Sprite Pencil", `sprite-pencil`, and `spritepencil` all agree.
        static func slug(_ text: String) -> String {
            String(text.lowercased().filter { $0.isLetter || $0.isNumber })
        }
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        try await GoogleSignIn.send(request, accessToken: try await validAccessToken(), service: Self.service) { accessToken = nil }
    }
}
