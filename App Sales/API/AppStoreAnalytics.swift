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

    static func + (lhs: AnalyticsDay, rhs: AnalyticsDay) -> AnalyticsDay {
        AnalyticsDay(
            impressions: lhs.impressions + rhs.impressions,
            pageViews: lhs.pageViews + rhs.pageViews,
            sessions: lhs.sessions + rhs.sessions,
            activeDevices: lhs.activeDevices + rhs.activeDevices)
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

    init(days: [String: [Date: AnalyticsDay]]) {
        let calendar = Calendar.autoupdatingCurrent
        let latest = days.values.flatMap(\.keys).max() ?? calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: 1, to: latest) ?? latest
        let start = calendar.date(byAdding: .day, value: -Self.windowDays, to: end) ?? latest
        self.range = start..<end
        self.days = days.mapValues { $0.filter { (start..<end).contains($0.key) } }
    }

    var isEmpty: Bool {
        days.values.allSatisfy(\.isEmpty)
    }

    /// Totals for one app, or for every app when `appleID` is `nil`.
    func totals(for appleID: String? = nil) -> AnalyticsTotals {
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
            averageDailyActiveDevices: daysWithSessions == 0 ? 0 : sum.activeDevices / daysWithSessions)
    }

    /// Analytics for the Demo account, in proportion to `ACData.example`'s downloads, so the
    /// conversion rates it prints are believable and the same on every launch.
    static func example(for data: ACData) -> AppStoreAnalytics {
        let calendar = Calendar.autoupdatingCurrent
        // A few days behind today, the way the real reports are.
        let latest = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -3, to: .now) ?? .now)

        var days: [String: [Date: AnalyticsDay]] = [:]
        for (index, app) in data.apps.enumerated() {
            for offset in 0..<windowDays {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: latest),
                      let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { continue }
                let downloads = Int(data.getTotal(for: .downloads, in: date..<nextDate, filteredApps: [app]))
                // The strongest seller converts best, so the ranking reads the same both ways.
                let impressionsPerDownload = 14 + index * 5
                days[app.appleID, default: [:]][date] = AnalyticsDay(
                    impressions: downloads * impressionsPerDownload,
                    pageViews: downloads * 3 + offset % 4,
                    sessions: downloads * (9 - index),
                    activeDevices: downloads * (6 - index) + offset % 3)
            }
        }
        return AppStoreAnalytics(days: days)
    }
}
