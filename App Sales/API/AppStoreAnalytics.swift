import Foundation

/// One app's App Store engagement and usage on one day, from App Store Connect's analytics reports.
struct AnalyticsDay: Codable, Hashable {
    /// Unique people who saw the app's icon in a list: search results, charts, the Today tab.
    var impressions = 0
    /// Unique people who were shown the app's product page.
    var pageViews = 0
    var sessions = 0
    /// Devices that opened the app at least once that day.
    var activeDevices = 0
    /// `activeDevices` by major OS version, every platform's together: 26 for iOS 26 and macOS 26
    /// alike, and `0` for anything before the year-numbered releases, whose numbers do not line up.
    /// A cache from before this was kept fails to decode, so its instances download again with it.
    var activeDevicesByOS: [Int: Int] = [:]

    /// The report's "Platform Version", such as "iOS 26.1", as a key of `activeDevicesByOS`.
    static func majorOS(_ platformVersion: String?) -> Int {
        let number = platformVersion?.split(separator: " ").first(where: { $0.first?.isNumber == true })
        let major = number.flatMap { Int($0.prefix(while: \.isNumber)) } ?? 0
        return major >= 26 ? major : 0
    }

    static func + (lhs: AnalyticsDay, rhs: AnalyticsDay) -> AnalyticsDay {
        AnalyticsDay(
            impressions: lhs.impressions + rhs.impressions,
            pageViews: lhs.pageViews + rhs.pageViews,
            sessions: lhs.sessions + rhs.sessions,
            activeDevices: lhs.activeDevices + rhs.activeDevices,
            activeDevicesByOS: lhs.activeDevicesByOS.merging(rhs.activeDevicesByOS, uniquingKeysWith: +))
    }
}

/// App Store analytics over a window, summed or averaged the way the home screen reports them.
struct AnalyticsTotals {
    let impressions: Int
    let pageViews: Int
    let sessions: Int
    /// Averaged over the days that have data rather than summed: the same device opens an app on
    /// many days, so a sum would count people several times over.
    let averageDailyActiveDevices: Int
    /// `averageDailyActiveDevices` by major OS version, keyed as `AnalyticsDay.activeDevicesByOS`.
    let averageDailyActiveDevicesByOS: [Int: Int]

    /// First-time downloads as a share of unique impressions, which is how App Store Connect
    /// defines conversion rate. `nil` when nobody saw the app, rather than a division by zero.
    func conversionRate(downloads: Int) -> Double? {
        guard impressions > 0 else { return nil }

        return Double(downloads) / Double(impressions)
    }
}

/// The analytics App Store Connect had for an account's apps, over the latest 30 days it has.
///
/// The analytics reports lag the sales reports by a few days, so the window ends on the last day
/// the reports cover rather than today. Compare against sales over `range`, not the home screen's
/// own 30 days, or downloads and page views would be counted over different days.
struct AppStoreAnalytics {

    static let windowDays = 30

    /// Keyed by the app's Apple ID, then by the start of each day.
    let days: [String: [Date: AnalyticsDay]]
    let range: Range<Date>
    /// The 30 days before `range`, which trends compare against.
    let previousRange: Range<Date>
    /// `days`, over `previousRange`. Empty unless the reports reach back across all of it, so a
    /// trend never compares a full window with a part of one.
    private let previousDays: [String: [Date: AnalyticsDay]]

    init(days: [String: [Date: AnalyticsDay]]) {
        let calendar = Calendar.autoupdatingCurrent
        let latest = days.values.flatMap(\.keys).max() ?? calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: 1, to: latest) ?? latest
        let start = calendar.date(byAdding: .day, value: -Self.windowDays, to: end) ?? latest
        let previousStart = calendar.date(byAdding: .day, value: -Self.windowDays, to: start) ?? start
        self.range = start..<end
        self.previousRange = previousStart..<start
        self.days = days.mapValues { $0.filter { (start..<end).contains($0.key) } }
        // A day's grace, as an app can go a day without a single view.
        let earliest = days.values.flatMap(\.keys).min() ?? latest
        let reachesBack = earliest <= (calendar.date(byAdding: .day, value: 1, to: previousStart) ?? previousStart)
        self.previousDays = reachesBack ? days.mapValues { $0.filter { (previousStart..<start).contains($0.key) } } : [:]
    }

    var isEmpty: Bool {
        days.values.allSatisfy(\.isEmpty)
    }

    /// Totals for one app, or for every app when `appleID` is `nil`.
    func totals(for appleID: String? = nil) -> AnalyticsTotals {
        Self.totals(of: days, for: appleID)
    }

    /// Totals over `previousRange`, or `nil` when the reports do not reach back that far.
    func previousTotals(for appleID: String? = nil) -> AnalyticsTotals? {
        previousDays.values.allSatisfy(\.isEmpty) ? nil : Self.totals(of: previousDays, for: appleID)
    }

    private static func totals(of days: [String: [Date: AnalyticsDay]], for appleID: String?) -> AnalyticsTotals {
        let apps = appleID.map { [days[$0] ?? [:]] } ?? Array(days.values)
        let byDate = apps.reduce(into: [Date: AnalyticsDay]()) { result, app in
            result.merge(app, uniquingKeysWith: +)
        }
        let sum = byDate.values.reduce(AnalyticsDay(), +)
        let daysWithSessions = byDate.values.count(where: { $0.sessions > 0 })

        return AnalyticsTotals(
            impressions: sum.impressions,
            pageViews: sum.pageViews,
            sessions: sum.sessions,
            averageDailyActiveDevices: daysWithSessions == 0 ? 0 : sum.activeDevices / daysWithSessions,
            averageDailyActiveDevicesByOS: daysWithSessions == 0 ? [:] : sum.activeDevicesByOS.mapValues { $0 / daysWithSessions })
    }

    /// Analytics for the Demo account, in proportion to `ACData.example`'s downloads, so the
    /// conversion rates it prints are believable and the same on every launch.
    static func example(for data: ACData) -> AppStoreAnalytics {
        let calendar = Calendar.autoupdatingCurrent
        // A few days behind today, the way the real reports are.
        let latest = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -3, to: .now) ?? .now)

        var days: [String: [Date: AnalyticsDay]] = [:]
        for (index, app) in data.apps.enumerated() {
            for offset in 0..<windowDays * 2 {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: latest),
                      let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { continue }
                let downloads = Int(data.getTotal(for: .downloads, in: date..<nextDate, filteredApps: [app]))
                // The strongest seller converts best, so the ranking reads the same both ways.
                let impressionsPerDownload = 14 + index * 5
                let activeDevices = downloads * (6 - index) + offset % 3
                days[app.appleID, default: [:]][date] = AnalyticsDay(
                    impressions: downloads * impressionsPerDownload,
                    pageViews: downloads * 3 + offset % 4,
                    sessions: downloads * (9 - index),
                    activeDevices: activeDevices,
                    // Most on this year's release, a good share on last year's, a few further back.
                    activeDevicesByOS: [27: activeDevices * 6 / 10, 26: activeDevices * 3 / 10, 0: activeDevices - activeDevices * 9 / 10])
            }
        }
        return AppStoreAnalytics(days: days)
    }
}
