import WidgetKit
import SwiftUI
import AppIntents

/// The configuration, timeline provider, and entry every App Sales widget is built on — the home
/// screen widgets on iPhone, iPad, Mac, and Vision, and the watch face complications. They differ
/// only in which views they render, so the fetching and refresh cadence live here rather than in
/// either extension.

struct WidgetPreferences: WidgetConfigurationIntent {
    
    static var title: LocalizedStringResource = "Select Account"
    static var description = IntentDescription("Selects the account to display information for.")

    @Parameter(title: "Account")
    var account: Account?
    
    @Parameter(title: "Advanced", default: true)
    var advanced: Bool

    init() { }
    init(account: Account, advanced: Bool) {
        self.account = account
        self.advanced = advanced
    }
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ACStatEntry {
        ACStatEntry(date: Date(), data: .example, configuration: WidgetPreferences())
    }

    func snapshot(for configuration: WidgetPreferences, in context: Context) async -> ACStatEntry {
        if context.isPreview {
            return .placeholder
        } else {
            do {
                let data = try await getApiData(apiKey: configuration.account)
                let isNewData = data.getRawData(for: .proceeds, lastNDays: 3).contains { (proceed) -> Bool in
                    Calendar.current.isDateInToday(proceed.1) ||
                    Calendar.current.isDateInYesterday(proceed.1)
                }

                let entry = ACStatEntry(
                    date: Date(),
                    data: data,
                    configuration: configuration,
                    relevance: isNewData ? .high : .medium
                )
                return entry
            } catch let err {
                let entry = ACStatEntry(date: Date(), data: nil, error: err as? APIError ?? .unknown, configuration: configuration, relevance: .low)
                return entry
            }
        }
    }

    func timeline(for configuration: WidgetPreferences, in context: Context) async -> Timeline<ACStatEntry> {
        do {
            let data = try await getApiData(apiKey: configuration.account)
            let isNewData = data.getRawData(for: .proceeds, lastNDays: 3).contains { (proceed) -> Bool in
                Calendar.autoupdatingCurrent.isDateInToday(proceed.1) ||
                Calendar.autoupdatingCurrent.isDateInYesterday(proceed.1)
            }

            let entry = ACStatEntry(date: Date(), data: data, configuration: configuration, relevance: isNewData ? .high : .medium)

            return Timeline(entries: [entry], policy: .after(Provider.nextUpdate(having: data)))
        } catch let err as APIError {
            let entry = ACStatEntry(date: Date(), data: nil, error: err, configuration: configuration, relevance: .low)

            return Timeline(entries: [entry], policy: .after(Provider.nextUpdate(after: err)))
        } catch {
            let entry = ACStatEntry(date: Date(), data: nil, error: APIError.unknown, configuration: configuration, relevance: .low)

            return Timeline(entries: [entry], policy: .after(Provider.nextUpdate(after: .unknown)))
        }
    }

    // MARK: - Refresh cadence

    /// When to come back after a fetch that worked.
    ///
    /// These figures move at exactly three moments a day — App Store Connect publishes the previous
    /// day's report by 5am Pacific for the Americas, 5am Japan time for Japan, Australia, and New
    /// Zealand, and 5am central European time for everywhere else — so the next of those is the next
    /// moment worth waking for, and anything in between would fetch the same numbers again.
    ///
    /// Asking more often is not free: WidgetKit allows a widget somewhere around 40–70 reloads a
    /// day, shared with the AI usage widget in this same extension, and a timeline that spends the
    /// day's budget on identical figures has none left when the day's report actually lands. Waking
    /// on the boundaries is both cheaper and fresher than the clock-based cadence this replaces,
    /// which slept through every afternoon and evening.
    static func nextUpdate(having data: ACData, at date: Date = .now) -> Date {
        let boundary = nextReportTime(after: date)

        // Apple publishes late often enough to be worth allowing for: with yesterday still missing
        // after every region has had its turn, waiting for the next boundary would leave the day
        // blank until tomorrow.
        guard Calendar.autoupdatingCurrent.isDateInYesterday(data.latestReportingDate()) || !reportsAreDue(at: date) else {
            return min(boundary, date.addingTimeInterval(2 * 60 * 60))
        }

        return boundary
    }

    /// When to come back after a fetch that failed. Credentials that are not valid stay not valid
    /// until the reader fixes them in the app — which reloads the timelines itself — so there is
    /// nothing to gain by asking again soon, and a busy retry would leave no budget for the moment
    /// they do.
    static func nextUpdate(after error: APIError, at date: Date = .now) -> Date {
        date.addingTimeInterval(error == .invalidCredentials ? 60 * 60 : 15 * 60)
    }

    /// The zones whose 5am publishes a region's daily report.
    private static let reportTimeZones = ["America/Los_Angeles", "Asia/Tokyo", "Europe/Berlin"]
    private static let reportHour = 5
    /// 5am is when a region's report starts arriving rather than when it has arrived.
    private static let reportGrace: TimeInterval = 30 * 60

    /// The next moment a region publishes, whichever region that is.
    static func nextReportTime(after date: Date) -> Date {
        let times = reportTimeZones.compactMap { identifier -> Date? in
            guard let timeZone = TimeZone(identifier: identifier) else { return nil }

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            // Searching from before the grace period so a boundary that has struck but whose grace
            // has not run out is still ahead, rather than skipping a day to the next one.
            return calendar.nextDate(
                after: date.addingTimeInterval(-reportGrace),
                matching: DateComponents(hour: reportHour),
                matchingPolicy: .nextTime)?
                .addingTimeInterval(reportGrace)
        }

        // Never sooner than a quarter hour, whatever the arithmetic says.
        return max(times.min() ?? date.addingTimeInterval(4 * 60 * 60), date.addingTimeInterval(15 * 60))
    }

    /// Whether every region has had time to publish yesterday's report. The last to do so is the
    /// Americas, whose 5am is the afternoon in Europe.
    private static func reportsAreDue(at date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: reportTimeZones[0]) ?? .autoupdatingCurrent
        // Built from the day's own components rather than `date(bySettingHour:)`, which searches
        // forward and so answers with tomorrow's 5am for any moment after this morning's.
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = reportHour
        guard let due = calendar.date(from: components) else { return false }

        return date > due.addingTimeInterval(reportGrace)
    }

    #if os(watchOS)
    /// The options the watch face gallery offers before the wearer configures anything: one per
    /// account already in the Keychain.
    func recommendations() -> [AppIntentRecommendation<WidgetPreferences>] {
        AccountManager.shared.accounts.map { account in
            AppIntentRecommendation(intent: WidgetPreferences(account: account, advanced: true), description: Text(account.name))
        }
    }
    #endif

    func getApiData(apiKey: Account?) async throws -> ACData {
        guard let apiKey,
              AccountManager.shared.getApiKey(apiKeyId: apiKey.id) != nil else {
                  throw APIError.invalidCredentials
              }
        let api = AppStoreConnectAPI(apiKey: apiKey)
        return try await api.getData()
    }
}

struct ACStatEntry: TimelineEntry {

    let date: Date
    let summary: PerformanceSummary?
    var error: APIError?
    let configuration: WidgetPreferences
    var relevance: TimelineEntryRelevance?
    
    init(date: Date, data: ACData?, error: APIError? = nil, configuration: WidgetPreferences, relevance: TimelineEntryRelevance? = nil) {
        self.date = date
        self.summary = data?.getPerformanceSummary()
        self.error = error
        self.configuration = configuration
        self.relevance = relevance
    }
    
    static let placeholder = ACStatEntry(date: Date(), data: .example, configuration: WidgetPreferences())
}

extension TimelineEntryRelevance {
    static let low = TimelineEntryRelevance(score: 0, duration: 0)
    static let medium = TimelineEntryRelevance(score: 50, duration: 60 * 60)
    static let high = TimelineEntryRelevance(score: 100, duration: 60 * 60)
}
