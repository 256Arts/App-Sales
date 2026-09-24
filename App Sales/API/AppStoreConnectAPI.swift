import Foundation
import AppStoreConnect_Swift_SDK
import Gzip
import SwiftCSV

final class AppStoreConnectAPI {
    private let privateKeyMinLength = 100

    private var account: Account

    init(apiKey: Account) {
        self.account = apiKey
    }

    private var privateKey: String { account.privateKey }
    private var vendorNumber: String { account.vendorNumber }

    static private var lastData: [Account: LoaderStatus] = [:]
    private enum LoaderStatus {
        case inProgress(Task<ACData, Error>)
        case loaded((data: ACData, date: Date))
    }

    static func clearMemoization() {
        lastData.removeAll()
    }

    public func getData(numOfDays: Int = ACDataCache.retainedDays, useCache: Bool = true) async throws -> ACData {
        if account.isDemo { return ACData.example }
        return try await getData(currency: Currency(rawValue: Locale.autoupdatingCurrent.currency?.identifier ?? ""), numOfDays: numOfDays, useCache: useCache)
    }

    public func getData(currency: Currency? = nil, numOfDays: Int = ACDataCache.retainedDays, useCache: Bool = true, useMemoization: Bool = true) async throws -> ACData {
        if account.isDemo { return ACData.example }

        if useMemoization {
            if let last = AppStoreConnectAPI.lastData[account] {
                switch last {
                case .loaded(let res):
                    if res.date.timeIntervalSinceNow > -60 * 5 {
                        return res.data.changeCurrency(to: currency ?? .USD)
                    } else {
                        AppStoreConnectAPI.lastData.removeValue(forKey: account)
                    }
                case .inProgress(let task):
                    return try await task.value.changeCurrency(to: currency ?? .USD)
                }
            }
        }

        let task: Task<ACData, Error> = Task {
            return try await getDataFromAPI(localCurrency: currency ?? .USD, numOfDays: numOfDays, useCache: useCache)
        }

        AppStoreConnectAPI.lastData[account] = .inProgress(task)

        let data = try await task.value

        AppStoreConnectAPI.lastData[account] = .loaded((data, .now))

        return data
    }

    private func getDataFromAPI(localCurrency: Currency, numOfDays: Int = ACDataCache.retainedDays, useCache: Bool = true) async throws -> ACData {
        if self.privateKey.count < privateKeyMinLength {
            throw APIError.invalidCredentials
        }

        let provider = try account.apiProvider()

        var entries: [Event] = []

        await CurrencyConverter.shared.updateExchangeRates()

        let dates = Date.now.dayBefore.getLastNDates(numOfDays).map({ $0.acApiFormat() })

        var knownEmptyDates: Set<String> = []
        if useCache, let cached = ACDataCache.getData(apiKey: self.account) {
            entries.append(contentsOf: cached.data.changeCurrency(to: localCurrency).entries)
            // The latest couple of days may be empty only because Apple hasn't published them yet, so they're always re-requested.
            knownEmptyDates = cached.emptyDates.subtracting(dates.prefix(2))
        }

        let entriesDates = Set(entries.map({ $0.date.acApiFormat() }))
        let missingDates = dates.filter({ !entriesDates.contains($0) && !knownEmptyDates.contains($0) })

        async let results: [(date: String, data: Data?)] = withThrowingTaskGroup(of: (date: String, data: Data?).self) { group in
            var results: [(date: String, data: Data?)] = []

            for date in missingDates {
                group.addTask {
                    do {
                        return (date, try await self.salesReport(provider: provider, date: date))
                    } catch APIError.noDataAvailable {
                        return (date, nil)
                    }
                }
            }

            for try await result in group {
                results.append(result)
            }

            return results
        }

        var emptyDates: Set<String> = []
        for result in try await results {
            if let data = result.data {
                entries.append(contentsOf: parseApiResult(data, localCurrency: localCurrency))
            } else {
                emptyDates.insert(result.date)
            }
        }

        let apps = try? await self.getApps(entries: entries)
        let acdata = ACData(entries: entries, currency: localCurrency, apps: apps ?? [])
        ACDataCache.saveData(data: acdata, emptyDates: emptyDates, apiKey: self.account)

        return acdata
    }

    private func parseApiResult(_ result: Data, localCurrency: Currency) -> [Event] {
        var entries: [Event] = []

        guard let decompressedData = try? result.gunzipped() else {
            #if DEBUG
            fatalError()
            #else
            return []
            #endif
        }

        let str = String(decoding: decompressedData, as: UTF8.self)

        guard let tsv: CSV = try? CSV<Enumerated>(string: str, delimiter: "\t") else {
            #if DEBUG
            fatalError()
            #else
            return []
            #endif
        }

        try? tsv.enumerateAsDict { dict in
            let parentId: String = dict["Parent Identifier"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let sku: String = dict["SKU"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            var proceeds = Double(dict["Developer Proceeds"] ?? "0.00") ?? 0
            if let cur: Currency = Currency(rawValue: dict["Currency of Proceeds"] ?? "") {
                proceeds = CurrencyConverter.shared.convert(proceeds, valueCurrency: cur, outputCurrency: localCurrency) ?? 0
            } else {
                proceeds = 0
            }

            let newEntry = Event(appTitle: dict["Title"] ?? "UNKNOWN",
                                   appSKU: parentId.isEmpty ? sku : parentId,
                                   units: Int(dict["Units"] ?? "0") ?? 0,
                                   proceeds: Float(proceeds),
                                   date: Date.fromACFormat(dict["Begin Date"] ?? "") ?? Date.distantPast,
                                   countryCode: dict["Country Code"] ?? "UNKNOWN",
                                   device: dict["Device"] ?? "UNKNOWN",
                                   appIdentifier: dict["Apple Identifier"] ?? "",
                                   type: EventType(dict["Product Type Identifier"]))
            entries.append(newEntry)
        }
        return entries
    }

    private func getApps(entries: [Event]) async throws -> [ACApp] {
        // An in-app purchase row carries the purchase's own Apple ID, which is not an app, so only app
        // rows become requests.
        var requests: [String: ITunesAppRequest] = [:]
        var countrySales: [String: [String: Int]] = [:]
        for entry in entries where entry.type != .iap && entry.type != .restoredIap {
            if requests[entry.appIdentifier] == nil {
                requests[entry.appIdentifier] = .init(appleID: entry.appIdentifier, name: entry.appTitle, sku: entry.appSKU, storefront: nil, isApp: false)
            }
            countrySales[entry.appIdentifier, default: [:]][entry.countryCode, default: 0] += max(entry.units, 1)
            if [.download, .redownload, .update].contains(entry.type) {
                requests[entry.appIdentifier]?.isApp = true
            }
        }
        for appleID in requests.keys {
            // The storefront outside the US it sold best in, for an app the US lookup cannot see.
            requests[appleID]?.storefront = countrySales[appleID]?.filter { $0.key != "US" }.max(by: { $0.value < $1.value })?.key
        }

        return await withTaskGroup(of: ACApp?.self) { group in
            var lookUps: [ACApp] = []
            lookUps.reserveCapacity(requests.count)

            for app in requests.values {
                group.addTask {
                    if let found = try? await self.iTunesLookup(appRequest: app, country: nil) {
                        return found
                    }
                    if let storefront = app.storefront, let found = try? await self.iTunesLookup(appRequest: app, country: storefront) {
                        return found
                    }
                    // Removed from sale or unreleased: keep it from the report alone, so its sales
                    // still have a row, drawn with a placeholder icon.
                    guard app.isApp else { return nil }
                    return ACApp(appleID: app.appleID, name: app.name, sku: app.sku, version: "", price: 0, currentVersionReleaseDate: "", iconURL100: nil, iconURL512: nil)
                }
            }

            for await app in group {
                if let app = app {
                    lookUps.append(app)
                }
            }

            return lookUps
        }
    }

    private func salesReport(provider: APIProvider, date: String) async throws -> Data {
        print("Loading data for: \(date)")
        do {
            return try await provider.request(APIEndpoint.v1.salesReports.get(parameters: .init(
                filterVendorNumber: [vendorNumber],
                filterReportType: [.sales],
                filterReportSubType: [.summary],
                filterFrequency: [.daily],
                filterReportDate: [date])))
        } catch APIProvider.Error.requestFailure(404, _, _) {
            // A day with no sales, or one Apple has not published yet ("Report is not available
            // yet") — either way that day is empty, not the whole fetch failed.
            throw APIError.noDataAvailable
        } catch {
            throw APIError(error)
        }
    }

    private struct ITunesResponse: Codable {
        let resultCount: Int
        let results: [ITunesAppData]
    }

    private struct ITunesAppData: Codable {
        let artworkUrl512: String
        let artworkUrl100: String
        let currentVersionReleaseDate: String
        let version: String
        let price: Double
    }

    private struct ITunesAppRequest {
        let appleID: String
        let name: String
        let sku: String
        var storefront: String?
        /// Whether any row was a download, redownload, or update — the rows only an app has.
        var isApp: Bool
    }

    // Icons come from the public iTunes lookup rather than App Store Connect. The ASC API only exposes
    // icons per build (`Build.iconAssetToken`, via /v1/builds?filter[app]=…), which needs a Developer,
    // App Manager, or Admin key — Sales/Finance keys can read reports but not builds.
    // The lookup is per storefront (US unless `country` is given) and finds nothing for a removed or
    // unreleased app; `getApps` retries and then falls back to the report row.
    private func iTunesLookup(appRequest: ITunesAppRequest, country: String?) async throws -> ACApp {
        var query = "https://itunes.apple.com/lookup?id=" + appRequest.appleID
        if let country {
            query += "&country=" + country.lowercased()
        }
        guard let url = URL(string: query) else {
            throw APIError.unknown
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let appData = try? JSONDecoder().decode(ITunesResponse.self, from: data).results.first,
              let iconURL100 = URL(string: appData.artworkUrl100),
              let iconURL512 = URL(string: appData.artworkUrl512) else {
            throw APIError.unknown
        }

        let app = ACApp(
            appleID: appRequest.appleID,
            name: appRequest.name,
            sku: appRequest.sku,
            version: appData.version,
            price: appData.price,
            currentVersionReleaseDate: appData.currentVersionReleaseDate,
            iconURL100: iconURL100,
            iconURL512: iconURL512)
        Task {
            await app.saveIcon()
        }

        return app
    }
}

extension Account {
    /// A client for this account's key. A key that is not a valid .p8 is reported as bad credentials,
    /// the same as one App Store Connect rejects.
    func apiProvider() throws -> APIProvider {
        do {
            return APIProvider(configuration: try APIConfiguration(issuerID: issuerID, privateKeyID: privateKeyID, privateKey: privateKey))
        } catch {
            throw APIError.invalidCredentials
        }
    }
}

extension APIError {
    /// The app's reading of an App Store Connect SDK failure.
    init(_ error: Error) {
        if let error = error as? APIError {
            self = error
            return
        }
        guard let error = error as? APIProvider.Error else {
            self = .failed(error.localizedDescription)
            return
        }

        switch error {
        case .requestFailure(401, _, _), .requestGeneration:
            self = .invalidCredentials
        case .requestFailure(403, _, _):
            self = .wrongPermissions
        case .requestFailure(429, _, _):
            self = .exceededLimit
        case .requestFailure(404, let response, _) where response?.errors?.contains(where: { $0.detail?.contains("The request expected results but none were found") == true }) == true:
            self = .noDataAvailable
        case .requestFailure(let status, let response, _):
            let detail = response?.errors?.compactMap { $0.detail ?? $0.title }.first
            self = .failed("App Store Connect returned an error (\(status))" + (detail.map { ": \($0)" } ?? "."))
        default:
            self = .failed(error.localizedDescription)
        }
    }
}

extension Date {
    func acApiFormat() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: self)
    }

    static func fromACFormat(_ dateString: String) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/yyyy"
        return dateFormatter.date(from: dateString)
    }

    func getLastNDates(_ n: Int) -> [Date] {
        if n == 0 { return [] }
        let cal = NSCalendar.current
        // start with today
        var date = cal.startOfDay(for: self)

        var res: [Date] = []

        for _ in 1 ... max(1, n) {
            res.append(date)
            if let nextDate = cal.date(byAdding: Calendar.Component.day, value: -1, to: date) {
                date = nextDate
            }
        }
        return res
    }
}
