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

    public func getData(numOfDays: Int = 60, useCache: Bool = true) async throws -> ACData {
        if account.isDemo { return ACData.example }
        return try await getData(currency: Currency(rawValue: Locale.autoupdatingCurrent.currency?.identifier ?? ""), numOfDays: numOfDays, useCache: useCache)
    }

    public func getData(currency: Currency? = nil, numOfDays: Int = 60, useCache: Bool = true, useMemoization: Bool = true) async throws -> ACData {
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

    private func getDataFromAPI(localCurrency: Currency, numOfDays: Int = 60, useCache: Bool = true) async throws -> ACData {
        if self.privateKey.count < privateKeyMinLength {
            throw APIError.invalidCredentials
        }

        let provider = try account.apiProvider()

        var entries: [Event] = []

        await CurrencyConverter.shared.updateExchangeRates()

        let dates = Date.now.dayBefore.getLastNDates(numOfDays).map({ $0.acApiFormat() })

        if useCache {
            let cachedData = ACDataCache.getData(apiKey: self.account)?.changeCurrency(to: localCurrency)
            let cachedEntries: [Event] = cachedData?.entries ?? []

            entries.append(contentsOf: cachedEntries)
        }

        let entriesDates = entries.map({ $0.date.acApiFormat() })
        let missingDates = dates.filter({ !entriesDates.contains($0) })

        async let results: [Data] = withThrowingTaskGroup(of: Data?.self) { group in
            var data: [Data] = []

            for date in missingDates {
                group.addTask {
                    do {
                        return try await self.salesReport(provider: provider, date: date)
                    } catch APIError.noDataAvailable {
                        return nil
                    }
                }
            }

            for try await d in group {
                if let d = d {
                    data.append(d)
                }
            }

            return data
        }

        for result in try await results {
            entries.append(contentsOf: parseApiResult(result, localCurrency: localCurrency))
        }

        let apps = try? await self.getApps(entries: entries)
        let acdata = ACData(entries: entries, currency: localCurrency, apps: apps ?? [])
        ACDataCache.saveData(data: acdata, apiKey: self.account)

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
        let tupples: [ITunesAppRequest] = entries.map({ .init(appleID: $0.appIdentifier, name: $0.appTitle, sku: $0.appSKU) })
        var uniqueTupple: [ITunesAppRequest] = []
        for tupple in tupples {
            if !uniqueTupple.contains(where: { $0.appleID == tupple.appleID }) {
                uniqueTupple.append(tupple)
            }
        }

        return await withTaskGroup(of: ACApp?.self) { group in
            var lookUps: [ACApp] = []
            lookUps.reserveCapacity(uniqueTupple.count)

            for app in uniqueTupple {
                group.addTask {
                    return try? await self.iTunesLookup(appRequest: app)
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
    }

    // Icons come from the public iTunes lookup rather than App Store Connect. The ASC API only exposes
    // icons per build (`Build.iconAssetToken`, via /v1/builds?filter[app]=…), which needs a Developer,
    // App Manager, or Admin key — Sales/Finance keys can read reports but not builds.
    // Known gap: this lookup throws for removed, unreleased, or non-US apps (no `country` param), and
    // `getApps` then drops the app entirely. If fixing, fall back to the latest build's icon, then a placeholder.
    private func iTunesLookup(appRequest: ITunesAppRequest) async throws -> ACApp {
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=" + appRequest.appleID) else {
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
            self = .unknown
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
        default:
            self = .unknown
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
