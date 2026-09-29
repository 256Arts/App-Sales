import Foundation
import AppStoreConnect_Swift_SDK
import Gzip
import SwiftCSV

/// What App Store Connect could give back for an account's analytics.
enum AnalyticsAvailability {
    case ready(AppStoreAnalytics)
    /// Reports have been requested, but App Store Connect has not generated any yet. The first ones
    /// take a day or two.
    case preparing
    /// No app has reports turned on, and this key cannot turn them on: requesting reports needs
    /// the Admin role, though reading them afterwards only needs Sales and Reports or Finance.
    case needsAdminKey
}

/// Fetches App Store engagement and app usage from App Store Connect's Analytics Reports API.
///
/// The API is asynchronous. An Admin asks, once per app, for ongoing reports; App Store Connect then
/// publishes a report instance every day, and each instance is one or more gzipped files. So a
/// first fetch turns the reports on and has nothing to show, and every later fetch downloads only
/// the instances it has not already summarized — which `AnalyticsCache` keeps, because an app has
/// a new one per report per day and the rate limit is 3,600 requests an hour.
final class AnalyticsReportsAPI {

    private let account: Account

    init(account: Account) {
        self.account = account
    }

    /// The two reports read, and how each row adds to a day.
    enum Report: String, Codable, CaseIterable {
        case discovery = "App Store Discovery and Engagement Standard"
        case sessions = "App Sessions Standard"

        func day(from row: [String: String]) -> AnalyticsDay {
            func int(_ column: String) -> Int { Int(row[column] ?? "") ?? 0 }

            switch self {
            case .discovery:
                switch row["Event"] {
                case "Impression": return AnalyticsDay(impressions: int("Unique Counts"))
                case "Page view": return AnalyticsDay(pageViews: int("Unique Counts"))
                default: return AnalyticsDay()
                }
            case .sessions:
                return AnalyticsDay(sessions: int("Sessions"), activeDevices: int("Unique Devices"))
            }
        }
    }

    /// - Parameter appleIDs: the apps to report on, which are the ones the sales reports name.
    func getAnalytics(appleIDs: [String], sales: ACData) async throws -> AnalyticsAvailability {
        if account.isDemo { return .ready(.example(for: sales)) }

        let provider = try account.apiProvider()
        let results = try await withThrowingTaskGroup(of: AppResult.self) { group in
            for appleID in appleIDs {
                group.addTask { try await self.analytics(appleID: appleID, provider: provider) }
            }
            return try await group.reduce(into: [String: AppResult]()) { $0[$1.appleID] = $1 }
        }

        let days = results.compactMapValues(\.days)
        let analytics = AppStoreAnalytics(days: days)
        if !analytics.isEmpty {
            return .ready(analytics)
        } else if results.values.contains(where: { $0.status == .needsAdminKey }), !results.values.contains(where: { $0.status != .needsAdminKey }) {
            return .needsAdminKey
        } else {
            return .preparing
        }
    }

    // MARK: One App

    private struct AppResult {
        enum Status { case ready, preparing, needsAdminKey }

        let appleID: String
        let status: Status
        var days: [Date: AnalyticsDay]?
    }

    private func analytics(appleID: String, provider: APIProvider) async throws -> AppResult {
        do {
            return try await readAnalytics(appleID: appleID, provider: provider)
        } catch let error where APIError(error) == .wrongPermissions {
            // A key with neither Admin, Sales and Reports, nor Finance cannot read reports either.
            return AppResult(appleID: appleID, status: .needsAdminKey)
        } catch {
            throw APIError(error)
        }
    }

    private func readAnalytics(appleID: String, provider: APIProvider) async throws -> AppResult {
        guard let requestID = try await ongoingRequestID(appleID: appleID, provider: provider) else {
            do {
                try await createOngoingRequest(appleID: appleID, provider: provider)
                return AppResult(appleID: appleID, status: .preparing)
            } catch let error where APIError(error) == .wrongPermissions {
                return AppResult(appleID: appleID, status: .needsAdminKey)
            }
        }

        var instances: [AnalyticsCache.Instance] = []
        for report in Report.allCases {
            let reports = try await provider.request(APIEndpoint.v1.analyticsReportRequests.id(requestID).reports.get(parameters: .init(filterName: [report.rawValue])))
            guard let reportID = reports.data.first?.id else { continue }
            instances += try await summarizedInstances(reportID: reportID, report: report, appleID: appleID, provider: provider)
        }

        return AppResult(appleID: appleID, status: instances.isEmpty ? .preparing : .ready, days: AnalyticsCache.days(from: instances))
    }

    /// The app's ongoing report request, if one is still generating. A request App Store Connect
    /// stopped for inactivity no longer does, and a new one has to be made in its place.
    private func ongoingRequestID(appleID: String, provider: APIProvider) async throws -> String? {
        let requests = try await provider.request(APIEndpoint.v1.apps.id(appleID).analyticsReportRequests.get(parameters: .init(filterAccessType: [.ongoing])))
        return requests.data.first(where: { $0.attributes?.isStoppedDueToInactivity != true })?.id
    }

    private func createOngoingRequest(appleID: String, provider: APIProvider) async throws {
        let body = AnalyticsReportRequestCreateRequest(data: .init(
            type: .analyticsReportRequests,
            attributes: .init(accessType: .ongoing),
            relationships: .init(app: .init(data: .init(type: .apps, id: appleID)))))
        do {
            _ = try await provider.request(APIEndpoint.v1.analyticsReportRequests.post(body))
        } catch APIProvider.Error.requestFailure(409, _, _) {
            // Another device made the request first. Either way, reports are now on their way.
        }
    }

    /// Every daily instance of the report from the last few weeks, summarized by day. Instances
    /// already in the cache are not downloaded again: once published, one does not change.
    private func summarizedInstances(reportID: String, report: Report, appleID: String, provider: APIProvider) async throws -> [AnalyticsCache.Instance] {
        let oldest = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -(AppStoreAnalytics.windowDays + 10), to: .now) ?? .distantPast
        var recent: [(id: String, processingDate: String)] = []
        let listing = APIEndpoint.v1.analyticsReports.id(reportID).instances.get(parameters: .init(filterGranularity: [.daily], limit: 200))
        for try await page in provider.paged(listing) {
            for instance in page.data {
                guard let processingDate = instance.attributes?.processingDate,
                      (AnalyticsCache.date(from: processingDate) ?? .distantPast) >= oldest else { continue }
                recent.append((instance.id, processingDate))
            }
        }

        let cached = AnalyticsCache.instances(account: account)
        let instances = try await withThrowingTaskGroup(of: AnalyticsCache.Instance.self) { group in
            for instance in recent {
                if let hit = cached[instance.id] {
                    group.addTask { hit }
                } else {
                    group.addTask {
                        try await self.summarize(instanceID: instance.id, processingDate: instance.processingDate, report: report, appleID: appleID, provider: provider)
                    }
                }
            }
            return try await group.reduce(into: [AnalyticsCache.Instance]()) { $0.append($1) }
        }
        AnalyticsCache.save(instances, account: account)
        return instances
    }

    private func summarize(instanceID: String, processingDate: String, report: Report, appleID: String, provider: APIProvider) async throws -> AnalyticsCache.Instance {
        let segments = try await provider.request(APIEndpoint.v1.analyticsReportInstances.id(instanceID).segments.get())
        var days: [String: AnalyticsDay] = [:]
        for segment in segments.data {
            guard let url = segment.attributes?.url else { continue }
            // A pre-signed download link, fetched without the API's token.
            let (data, _) = try await URLSession.shared.data(from: url)
            let text = String(decoding: (try? data.gunzipped()) ?? data, as: UTF8.self)
            let delimiter: CSVDelimiter = text.prefix(while: { $0 != "\n" }).contains("\t") ? .tab : .comma
            let csv = try CSV<Named>(string: text, delimiter: delimiter)
            for row in csv.rows {
                guard let date = row["Date"] else { continue }
                days[date, default: AnalyticsDay()] = days[date, default: AnalyticsDay()] + report.day(from: row)
            }
        }
        return AnalyticsCache.Instance(id: instanceID, report: report, appleID: appleID, processingDate: processingDate, days: days)
    }
}

// MARK: - Cache

/// Summarized report instances, per account, in the App Group container beside the sales cache.
enum AnalyticsCache {

    struct Instance: Codable {
        let id: String
        let report: AnalyticsReportsAPI.Report
        let appleID: String
        /// `yyyy-MM-dd`, as App Store Connect sends it.
        let processingDate: String
        /// Keyed by the report's own `yyyy-MM-dd` dates.
        let days: [String: AnalyticsDay]
    }

    private typealias Storage = [String: [String: Instance]]

    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?.appending(path: "analytics-cache.json")
    }

    private static let lock = NSLock()

    static func instances(account: Account) -> [String: Instance] {
        lock.withLock { load()[account.id] ?? [:] }
    }

    /// Adds `instances`, and drops ones processed so long ago they can no longer fall in the window.
    static func save(_ instances: [Instance], account: Account) {
        let oldest = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -60, to: .now) ?? .distantPast
        lock.withLock {
            var storage = load()
            var accountInstances = storage[account.id] ?? [:]
            for instance in instances {
                accountInstances[instance.id] = instance
            }
            storage[account.id] = accountInstances.filter { (date(from: $0.value.processingDate) ?? .distantPast) >= oldest }
            guard let url, let data = try? JSONEncoder().encode(storage) else { return }
            try? data.write(to: url)
        }
    }

    static func clear(account: Account) {
        lock.withLock {
            var storage = load()
            storage[account.id] = nil
            guard let url, let data = try? JSONEncoder().encode(storage) else { return }
            try? data.write(to: url)
        }
    }

    private static func load() -> Storage {
        guard let url, let data = try? Data(contentsOf: url) else { return [:] }

        return (try? JSONDecoder().decode(Storage.self, from: data)) ?? [:]
    }

    /// One app's days, each taken from the latest instance of each report that covers it.
    ///
    /// Not summed across instances: App Store Connect republishes days — sometimes an identical
    /// instance twice, sometimes a correction — so adding every instance would count them twice.
    static func days(from instances: [Instance]) -> [Date: AnalyticsDay] {
        var latest: [AnalyticsReportsAPI.Report: [String: (processingDate: String, day: AnalyticsDay)]] = [:]
        for instance in instances {
            for (date, day) in instance.days where instance.processingDate >= (latest[instance.report]?[date]?.processingDate ?? "") {
                latest[instance.report, default: [:]][date] = (instance.processingDate, day)
            }
        }

        var result: [Date: AnalyticsDay] = [:]
        for (dateString, entry) in latest.values.joined() {
            guard let date = date(from: dateString) else { continue }
            result[date, default: AnalyticsDay()] = result[date, default: AnalyticsDay()] + entry.day
        }
        return result
    }

    /// The start of a `yyyy-MM-dd` day in the reader's calendar, which is how sales events are dated.
    static func date(from string: String) -> Date? {
        try? Date(string, strategy: Date.ISO8601FormatStyle(timeZone: .autoupdatingCurrent).year().month().day().dateSeparator(.dash))
    }
}
