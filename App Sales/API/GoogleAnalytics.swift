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
    /// Views over the 30 days before.
    let previousViews: Int
}

/// The reader's Google Analytics sign-ins, which of each one's properties are their websites, and
/// which page on them is about each app — so the home screen can put web page views next to downloads.
///
/// Signing in is the app's job (it needs a browser session); everything after that is plain HTTP, so
/// this stays watchOS-clean. The sign-ins are per reader rather than per App Store Connect account —
/// several, since a work site often sits behind a managed Google account — and traffic is read from
/// every chosen website at once, each app finding its own page by name. They live in the same
/// iCloud-synchronized Keychain, so they follow the reader to every device.
@MainActor
@Observable
final class GoogleAnalytics {

    static let shared = GoogleAnalytics()

    private static let service = "Google Analytics"

    private struct Connection: Codable {
        var account: GoogleAccount
        var websites: [GoogleAnalyticsProperty] = []
    }

    private struct Stored: Codable {
        var connections: [Connection] = []
        /// Keyed by the app's Apple ID.
        var pageURLs: [String: URL] = [:]
    }

    private var stored = Stored() {
        didSet { persist() }
    }
    @ObservationIgnored private let tokens = GoogleAccessTokens(service: service)

    var accounts: [GoogleAccount] { stored.connections.map(\.account) }
    var isConnected: Bool { !stored.connections.isEmpty }
    /// Every chosen website, across all sign-ins.
    var websites: [GoogleAnalyticsProperty] { stored.connections.flatMap(\.websites) }
    var pageURLs: [String: URL] { stored.pageURLs }

    private static let keychain = Keychain(service: "com.jaydenirwin.appsales")
        .synchronizable(true)
    private static let keychainKey = "google-analytics"

    private init() {
        // A screenshot run stays off the real Keychain, as `AccountManager` does.
        guard !ScreenshotMode.isActive,
              let data = try? Self.keychain.getData(Self.keychainKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }

        self.stored = stored
    }

    private func persist() {
        guard !ScreenshotMode.isActive else { return }

        if !stored.connections.isEmpty || !stored.pageURLs.isEmpty, let data = try? JSONEncoder().encode(stored) {
            try? Self.keychain.set(data, key: Self.keychainKey)
        } else {
            try? Self.keychain.remove(Self.keychainKey)
        }
    }

    func websites(of account: GoogleAccount) -> [GoogleAnalyticsProperty] {
        stored.connections.first { $0.account.id == account.id }?.websites ?? []
    }

    func setWebsite(_ property: GoogleAnalyticsProperty, isChosen: Bool, of account: GoogleAccount) {
        guard let index = stored.connections.firstIndex(where: { $0.account.id == account.id }) else { return }

        stored.connections[index].websites.removeAll { $0.id == property.id }
        if isChosen {
            stored.connections[index].websites.append(property)
        }
    }

    /// - Parameter url: `nil` forgets the app's page.
    func setPageURL(_ url: URL?, for appleID: String) {
        stored.pageURLs[appleID] = url
    }

    func disconnect(_ account: GoogleAccount) {
        stored.connections.removeAll { $0.account.id == account.id }
        tokens.remove(account)
    }

    // MARK: Sign In

    static func signInRequest() -> (url: URL, verifier: String) {
        GoogleSignIn.request(scope: "https://www.googleapis.com/auth/analytics.readonly")
    }

    /// Finishes signing in with the URL the browser session was redirected to. Signing in again as
    /// an account already here renews it, keeping its websites.
    func connect(callback: URL, verifier: String) async throws {
        let (token, account) = try await GoogleSignIn.finish(callback: callback, verifier: verifier)
        tokens.store(token, for: account)
        if let index = stored.connections.firstIndex(where: { $0.account.id == account.id }) {
            stored.connections[index].account = account
            return
        }

        stored.connections.append(Connection(account: account))
        // Most people have one website; do not make them pick it.
        let properties = try await properties(of: account)
        if properties.count == 1, let property = properties.first {
            setWebsite(property, isChosen: true, of: account)
        }
    }

    // MARK: Reading

    /// Every property the account can read, grouped the way Analytics lists them.
    func properties(of account: GoogleAccount) async throws -> [GoogleAnalyticsProperty] {
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

            let page: Page = try await send(URLRequest(url: components?.url ?? URL(filePath: "/")), as: account)
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
    /// keyed by Apple ID. An app's page is the one the reader set or, failing that, any page on any
    /// chosen website whose last path component spells the app's name — `256arts.com/spritepencil`
    /// for Sprite Pencil. Apps with no page are left out. A website that cannot be read is skipped,
    /// unless none can.
    func traffic(for apps: [(appleID: String, name: String)]) async throws -> [String: WebPageTraffic] {
        let reports = stored.connections.flatMap { connection in connection.websites.map { (connection.account, $0) } }
        guard !reports.isEmpty else { throw GoogleSignInError.notConnected(service: Self.service) }

        var pages: [WebPage: Int] = [:]
        var previousPages: [WebPage: Int] = [:]
        var failure: Error?
        await withTaskGroup(of: Result<PageViews, Error>.self) { group in
            for (account, property) in reports {
                group.addTask {
                    do { return .success(try await self.pages(of: property, as: account)) } catch { return .failure(error) }
                }
            }
            for await result in group {
                switch result {
                case .success(let report):
                    pages.merge(report.current, uniquingKeysWith: +)
                    previousPages.merge(report.previous, uniquingKeysWith: +)
                case .failure(let error): failure = error
                }
            }
        }
        if pages.isEmpty, let failure { throw failure }

        var traffic: [String: WebPageTraffic] = [:]
        for app in apps {
            if let url = pageURLs[app.appleID] {
                traffic[app.appleID] = WebPageTraffic(url: url, views: pages[WebPage(url)] ?? 0, previousViews: previousPages[WebPage(url)] ?? 0)
            } else if let match = Self.page(named: app.name, in: pages) {
                traffic[app.appleID] = WebPageTraffic(url: match.page.url, views: match.views, previousViews: previousPages[match.page] ?? 0)
            }
        }
        return traffic
    }

    private typealias PageViews = (current: [WebPage: Int], previous: [WebPage: Int])

    /// Every page of one website and its views, over the last 30 days and the 30 before. One report
    /// of every page, rather than one per app, so matching by name costs nothing extra.
    private func pages(of property: GoogleAnalyticsProperty, as account: GoogleAccount) async throws -> PageViews {
        struct Report: Decodable {
            struct Row: Decodable {
                struct Value: Decodable { let value: String }
                let dimensionValues: [Value]
                let metricValues: [Value]
            }
            let rows: [Row]?
        }

        let body: [String: Any] = [
            "dateRanges": [
                ["startDate": "30daysAgo", "endDate": "today", "name": "current"],
                ["startDate": "61daysAgo", "endDate": "31daysAgo", "name": "previous"],
            ],
            "dimensions": [["name": "hostName"], ["name": "pagePath"]],
            "metrics": [["name": "screenPageViews"]],
            "limit": 10_000,
        ]

        var request = URLRequest(url: URL(string: "https://analyticsdata.googleapis.com/v1beta/\(property.id):runReport") ?? URL(filePath: "/"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let report: Report = try await send(request, as: account)

        // The same page is often reachable with and without `www.` and a trailing slash; those count together.
        // With two date ranges, each row ends with a `dateRange` dimension naming its range.
        var pages: PageViews = ([:], [:])
        for row in report.rows ?? [] {
            guard row.dimensionValues.count == 3 else { continue }
            let page = WebPage(host: row.dimensionValues[0].value, path: row.dimensionValues[1].value)
            let views = Int(row.metricValues.first?.value ?? "") ?? 0
            if row.dimensionValues[2].value == "previous" {
                pages.previous[page, default: 0] += views
            } else {
                pages.current[page, default: 0] += views
            }
        }
        return pages
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

    private func send<T: Decodable>(_ request: URLRequest, as account: GoogleAccount) async throws -> T {
        do {
            return try await tokens.send(request, as: account)
        } catch GoogleSignInError.signInExpired {
            disconnect(account)
            throw GoogleSignInError.signInExpired(service: Self.service)
        }
    }
}
