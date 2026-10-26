import Foundation
import KeychainAccess
#if canImport(WidgetKit)
import WidgetKit
#endif

/// One app's AdMob earnings in one country on one day, in US dollars.
struct AdEarning: Codable, Hashable {
    /// The App Store app the AdMob app is linked to, when the reader linked it.
    let appStoreID: String?
    let appName: String
    let date: Date
    let countryCode: String
    let earnings: Double
}

/// The reader's AdMob connection, whose estimated earnings `AppStoreConnectAPI` adds to proceeds as
/// `.ad` events, so every proceeds figure — the summary, each app, the widgets — counts its ads.
///
/// Like `GoogleAnalytics`, one per reader and kept in the synchronizable Keychain, and plain HTTP
/// after sign-in, so the widget extensions and the watch read it too. Google's refresh tokens do not
/// rotate, so unlike `AIAssistants` several processes refreshing at once is harmless.
@MainActor
@Observable
final class AdMob {

    static let shared = AdMob()

    private static let service = "AdMob"

    private struct Connection: Codable {
        var refreshToken: String
        /// `accounts/pub-…`, the publisher account reports are run against.
        var account: String?
    }

    private var connection: Connection? {
        didSet { persist() }
    }
    private var accessToken: GoogleSignIn.Token?

    var isConnected: Bool { connection != nil }

    private static let keychain = Keychain(service: "com.jaydenirwin.appsales")
        .synchronizable(true)
    private static let keychainKey = "admob"

    private init() {
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

    func disconnect() {
        connection = nil
        accessToken = nil
        Cache.clear()
        salesChanged()
    }

    /// Proceeds memoized or drawn by a widget before the change no longer add up.
    private func salesChanged() {
        AppStoreConnectAPI.clearMemoization()
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    // MARK: Sign In

    static func signInRequest() -> (url: URL, verifier: String) {
        GoogleSignIn.request(scope: "https://www.googleapis.com/auth/admob.readonly")
    }

    /// Finishes signing in with the URL the browser session was redirected to.
    func connect(callback: URL, verifier: String) async throws {
        let (token, refreshToken) = try await GoogleSignIn.finish(callback: callback, verifier: verifier)
        accessToken = token
        connection = Connection(refreshToken: refreshToken)
        connection?.account = try await publisherAccount()
        salesChanged()
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

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        try await GoogleSignIn.send(request, accessToken: try await validAccessToken(), service: Self.service) { accessToken = nil }
    }

    // MARK: Reading

    private static let api = "https://admob.googleapis.com/v1/"

    /// A Google sign-in reaches a single AdMob publisher account.
    private func publisherAccount() async throws -> String {
        struct Response: Decodable {
            struct Account: Decodable { let name: String }
            let account: [Account]?
        }

        let response: Response = try await send(URLRequest(url: URL(string: Self.api + "accounts") ?? URL(filePath: "/")))
        guard let account = response.account?.first?.name else {
            throw GoogleSignInError.google(String(localized: "This Google account has no AdMob account."))
        }
        return account
    }

    /// Each app's earnings over the days the sales cache keeps, from the App Group cache while it is
    /// fresh. Earnings are AdMob's estimate, which is what its own dashboard shows until payment.
    func earnings() async throws -> [AdEarning] {
        guard let connection else { throw GoogleSignInError.notConnected(service: Self.service) }
        if let cached = Cache.earnings(newerThan: Cache.freshness) { return cached }

        let account: String
        if let saved = connection.account {
            account = saved
        } else {
            account = try await publisherAccount()
            self.connection?.account = account
        }

        async let linkedApps = appStoreIDs(account: account)
        let report = try await report(account: account)
        let appStoreIDs = (try? await linkedApps) ?? [:]

        let earnings = report.map {
            AdEarning(appStoreID: appStoreIDs[$0.appID], appName: $0.appName, date: $0.date, countryCode: $0.countryCode, earnings: $0.earnings)
        }
        Cache.save(earnings)
        return earnings
    }

    /// The App Store ID each AdMob app is linked to, keyed by its `ca-app-pub-…~…` ID.
    private func appStoreIDs(account: String) async throws -> [String: String] {
        struct Page: Decodable {
            struct App: Decodable {
                struct Linked: Decodable { let appStoreId: String? }
                let appId: String
                let linkedAppInfo: Linked?
            }
            let apps: [App]?
            let nextPageToken: String?
        }

        var ids: [String: String] = [:]
        var pageToken: String?
        repeat {
            var components = URLComponents(string: Self.api + account + "/apps")
            components?.queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
            if let pageToken { components?.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken)) }

            let page: Page = try await send(URLRequest(url: components?.url ?? URL(filePath: "/")))
            for app in page.apps ?? [] {
                ids[app.appId] = app.linkedAppInfo?.appStoreId
            }
            pageToken = page.nextPageToken
        } while pageToken?.isEmpty == false
        return ids
    }

    private struct ReportRow {
        let appID: String
        let appName: String
        let date: Date
        let countryCode: String
        let earnings: Double
    }

    private func report(account: String) async throws -> [ReportRow] {
        // The report streams a header, the rows, and a footer as elements of one array.
        struct Element: Decodable {
            struct Row: Decodable {
                struct Dimension: Decodable { let value: String?; let displayLabel: String? }
                struct Metric: Decodable { let microsValue: String? }
                let dimensionValues: [String: Dimension]
                let metricValues: [String: Metric]
            }
            let row: Row?
        }

        let calendar = Calendar.autoupdatingCurrent
        let end = calendar.dateComponents([.year, .month, .day], from: .now)
        let start = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: -ACDataCache.retainedDays, to: .now) ?? .now)
        func day(_ components: DateComponents) -> [String: Int] {
            ["year": components.year ?? 0, "month": components.month ?? 0, "day": components.day ?? 0]
        }

        let body: [String: Any] = [
            "reportSpec": [
                "dateRange": ["startDate": day(start), "endDate": day(end)],
                "dimensions": ["DATE", "APP", "COUNTRY"],
                "metrics": ["ESTIMATED_EARNINGS"],
                "localizationSettings": ["currencyCode": "USD"],
            ],
        ]

        var request = URLRequest(url: URL(string: Self.api + account + "/networkReport:generate") ?? URL(filePath: "/"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let elements: [Element] = try await send(request)

        // The same day an App Store report is dated by: local midnight.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return elements.compactMap(\.row).compactMap { row in
            guard let appID = row.dimensionValues["APP"]?.value,
                  let date = row.dimensionValues["DATE"]?.value.flatMap(formatter.date(from:)),
                  let micros = row.metricValues["ESTIMATED_EARNINGS"]?.microsValue.flatMap(Double.init),
                  micros > 0 else { return nil }

            return ReportRow(
                appID: appID,
                appName: row.dimensionValues["APP"]?.displayLabel ?? "",
                date: date,
                countryCode: row.dimensionValues["COUNTRY"]?.value ?? "UNKNOWN",
                earnings: micros / 1_000_000)
        }
    }

    /// The last report, in the App Group, so the app and the widget extensions share one fetch.
    private enum Cache {
        static let freshness: TimeInterval = 60 * 60

        private struct Contents: Codable {
            let fetched: Date
            let earnings: [AdEarning]
        }

        private static var storageURL: URL? {
            FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
                .appendingPathComponent("admob-cache.json")
        }

        static func earnings(newerThan maxAge: TimeInterval) -> [AdEarning]? {
            guard let storageURL, let data = try? Data(contentsOf: storageURL),
                  let contents = try? JSONDecoder().decode(Contents.self, from: data),
                  contents.fetched.timeIntervalSinceNow > -maxAge else { return nil }

            return contents.earnings
        }

        static func save(_ earnings: [AdEarning]) {
            guard let storageURL, let data = try? JSONEncoder().encode(Contents(fetched: .now, earnings: earnings)) else { return }

            try? data.write(to: storageURL)
        }

        static func clear() {
            guard let storageURL else { return }

            try? FileManager.default.removeItem(at: storageURL)
        }
    }
}

extension Event {
    /// An ad earning as a sale, so the proceeds sums count it. An AdMob app not linked to the App
    /// Store matches by name instead.
    static func ads(_ earnings: [AdEarning], apps: [ACApp], currency: Currency) -> [Event] {
        let byID = Dictionary(apps.map { ($0.appleID, $0) }, uniquingKeysWith: { first, _ in first })
        let byName = Dictionary(apps.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        return earnings.compactMap { earning in
            guard let app = earning.appStoreID.flatMap({ byID[$0] }) ?? byName[earning.appName.lowercased()] else { return nil }

            let proceeds = CurrencyConverter.shared.convert(earning.earnings, valueCurrency: .USD, outputCurrency: currency) ?? 0
            return Event(appTitle: app.name,
                         appSKU: app.sku,
                         units: 1,
                         proceeds: Float(proceeds),
                         date: earning.date,
                         countryCode: earning.countryCode,
                         device: "",
                         appIdentifier: app.appleID,
                         type: .ad)
        }
    }
}
