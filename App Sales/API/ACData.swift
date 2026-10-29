import Foundation
import SwiftUI

struct ACData: Codable {
    
    let apps: [ACApp]
    let entries: [Event]
    let displayCurrency: Currency

    init(entries: [Event], currency: Currency, apps: [ACApp]) {
        self.entries = entries
        self.displayCurrency = currency
        self.apps = apps
    }
    
    func changeCurrency(to outputCurrency: Currency) -> ACData {
        let newEntries: [Event] = self.entries.map({ entry -> Event in
            let proceeds = CurrencyConverter.shared.convert(Double(entry.proceeds),
                                                            valueCurrency: self.displayCurrency,
                                                            outputCurrency: outputCurrency) ?? 0
            return Event(appTitle: entry.appTitle,
                           appSKU: entry.appSKU,
                           units: entry.units,
                           proceeds: Float(proceeds),
                           date: entry.date,
                           countryCode: entry.countryCode,
                           device: entry.device,
                           appIdentifier: entry.appIdentifier,
                           type: entry.type)
        })

        return ACData(entries: newEntries, currency: outputCurrency, apps: self.apps)
    }
    
    func getEntries(for type: InfoType, startDate: Date, endDate: Date = .now, filteredApps: [ACApp] = []) -> [Event] {
        var entries = entries.getDays(start: startDate, end: endDate)
        if !filteredApps.isEmpty {
            entries = entries.filter { entry in
                filteredApps.contains(where: { $0.appleID == entry.appIdentifier })
            }
        }

        switch type {
        case .proceeds:
            entries = entries.filter({ $0.proceeds > 0 })
        case .downloads:
            if UserDefaults.shared?.bool(forKey: UserDefaults.Key.includeRedownloads) ?? false {
                entries = entries.filter({ $0.type == .download || $0.type == .redownload })
            } else {
                entries = entries.filter({ $0.type == .download })
            }
        case .updates:
            entries = entries.filter({ $0.type == .update })
        case .iap:
            entries = entries.filter({ $0.type == .iap || $0.type == .subscription })
        }

        return entries
    }

    func getRawData(for type: InfoType, lastNDays: Int, filteredApps: [ACApp] = []) -> [(Float, Date)] {
        let startDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -lastNDays, to: .now)!
        return getRawData(for: type, startDate: startDate, filteredApps: filteredApps)
    }
    
    func getRawData(for type: InfoType, startDate: Date, endDate: Date = .now, filteredApps: [ACApp] = []) -> [(Float, Date)] {
        let dict = Dictionary(grouping: getEntries(for: type, startDate: startDate, endDate: endDate, filteredApps: filteredApps), by: { $0.date })
        var result: [(Float, Date)]

        switch type {
        case .proceeds:
            result = dict.map { (key: Date, value: [Event]) -> (Float, Date) in
                return (value.reduce(0, { $0 + $1.proceeds * Float($1.units) }), key)
            }
        default:
            result = dict.map { (key: Date, value: [Event]) -> (Float, Date) in
                return (Float(value.reduce(0, { $0 + $1.units })), key)
            }
        }

        return result
    }

    // MARK: Get Device
    func getDevices(_ type: InfoType, lastNDays: Int, filteredApps: [ACApp] = []) -> [(String, Float)] {
        let startDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -lastNDays, to: .now)!
        let dict = Dictionary(grouping: getEntries(for: type, startDate: startDate, filteredApps: filteredApps), by: { $0.device })
        var result: [(String, Float)]

        switch type {
        case .proceeds:
            result = dict.map { (key: String, value: [Event]) -> (String, Float) in
                return (key, value.reduce(0, { $0 + $1.proceeds * Float($1.units) }))
            }
        default:
            result = dict.map { (key: String, value: [Event]) -> (String, Float) in
                return (key, Float(value.reduce(0, { $0 + $1.units })))
            }
        }

        return result
    }

    // MARK: Get Change
    func getChange(_ type: InfoType) -> Float {
        let latestInterval = getRawData(for: type, lastNDays: 15).map({ $0.0 }).reduce(0, +)
        let previousInterval = getRawData(for: type, lastNDays: 30).map({ $0.0 }).reduce(0, +) - latestInterval
        return ((latestInterval/previousInterval) - 1) * 100
    }
    
    func getChange(_ type: InfoType) -> String {
        let change = NSNumber(value: getChange(type))
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 1
        return nf.string(from: change) ?? "-"
    }
    
    /// One metric summed over a window: proceeds in the display currency, or a count of units.
    func getTotal(for type: InfoType, in range: Range<Date>, filteredApps: [ACApp] = []) -> Double {
        Double(getRawData(for: type, startDate: range.lowerBound, endDate: range.upperBound, filteredApps: filteredApps).reduce(0, { $0 + $1.0 }))
    }

    /// One metric for every day in `range`, oldest first, with days that sold nothing at zero
    /// rather than skipped, so a line drawn through them falls to the axis instead of across the gap.
    func dailyTotals(for type: InfoType, in range: Range<Date>, filteredApps: [ACApp] = []) -> [DailyValue] {
        let calendar = Calendar.autoupdatingCurrent
        let totals = Dictionary(getRawData(for: type, startDate: range.lowerBound, endDate: range.upperBound, filteredApps: filteredApps)
            .map { (calendar.startOfDay(for: $0.1), Double($0.0)) }, uniquingKeysWith: +)
        return sequence(first: calendar.startOfDay(for: range.lowerBound)) { calendar.date(byAdding: .day, value: 1, to: $0) }
            .prefix { $0 < range.upperBound }
            .map { DailyValue(date: $0, value: totals[$0] ?? 0) }
    }

    /// The 30-day-vs-previous-30-day rollup the home screen and the widget show.
    func getPerformanceSummary() -> PerformanceSummary {
        let thirtyDaysAgo = ACData.date(daysAgo: 30)

        return getPerformanceSummary(in: thirtyDaysAgo..<Date.now, comparedWith: ACData.date(daysAgo: 60)..<thirtyDaysAgo)
    }

    /// Totals over `range`, compared against `previousRange`. Both windows are passed in rather than
    /// one being derived from the other, so a caller reporting a single day stays on calendar days
    /// instead of drifting an hour across a daylight-saving boundary.
    func getPerformanceSummary(in range: Range<Date>, comparedWith previousRange: Range<Date>) -> PerformanceSummary {
        PerformanceSummary(
            downloads: Int(getTotal(for: .downloads, in: range)),
            prevDownloads: Int(getTotal(for: .downloads, in: previousRange)),
            proceeds: getTotal(for: .proceeds, in: range),
            prevProceeds: getTotal(for: .proceeds, in: previousRange),
            adProceeds: getAdTotal(in: range),
            prevAdProceeds: getAdTotal(in: previousRange),
            apps: getAppSummaries(in: range))
    }
    
    /// The AdMob earnings within `getTotal(for: .proceeds, …)`, in the display currency.
    func getAdTotal(in range: Range<Date>, filteredApps: [ACApp] = []) -> Double {
        Double(getEntries(for: .proceeds, startDate: range.lowerBound, endDate: range.upperBound, filteredApps: filteredApps)
            .filter { $0.type == .ad }
            .reduce(0) { $0 + $1.proceeds * Float($1.units) })
    }

    // MARK: Get by app
    func getAppSummaries() -> [AppPerformanceSummary] {
        getAppSummaries(in: ACData.date(daysAgo: 30)..<Date.now)
    }

    /// Every app on the App Store's downloads and proceeds over a window, best-selling first.
    func getAppSummaries(in range: Range<Date>) -> [AppPerformanceSummary] {
        apps
            .filter { $0.iconURL100 != nil }
            .map { app in
                AppPerformanceSummary(
                    appleID: app.appleID,
                    name: app.name,
                    iconURL: app.iconURL100,
                    downloads: Int(getTotal(for: .downloads, in: range, filteredApps: [app])),
                    proceeds: getTotal(for: .proceeds, in: range, filteredApps: [app]),
                    adProceeds: getAdTotal(in: range, filteredApps: [app]),
                    price: app.price)
            }
            .sorted(by: { $0.downloads > $1.downloads })
    }

    private static func date(daysAgo days: Int) -> Date {
        Calendar.autoupdatingCurrent.date(byAdding: .day, value: -days, to: .now) ?? .now
    }

    // MARK: Getting Dates
    /// The last day Apple reported. Ad earnings arrive the same day, so they do not count.
    func latestReportingDate() -> Date {
        return entries.filter({ $0.type != .ad }).map({ $0.date }).reduce(Date.distantPast, { $0 > $1 ? $0 : $1 })
    }
    
    static let example = createMockData(60)

    /// Mock sales for the Demo account, and so for the App Store screenshots taken from it.
    ///
    /// Seeded rather than freely random: the same numbers on every launch, and the same chart in
    /// every screenshot run. Days are offsets from today rather than fixed dates, so the shots do
    /// not drift with the month they were taken in either.
    private static func createMockData(_ days: Int) -> ACData {
        var entries: [Event] = []
        let apps: [ACApp] = [.demo1, .demo2, .demo3, .demo4]
        let countries = ["US", "DE", "ES", "UK", "IN", "CA", "SE", "NZ"]
        let devices = ["Desktop", "iPhone", "iPad"]
        var generator = SeededGenerator(seed: 20260904)

        for day in -days...0 {
            // Every app on every day, so no app can lose its bar in the chart to an unlucky draw.
            for (index, app) in apps.enumerated() {
                // The first app is the strongest seller and the last the weakest, which is also the
                // order `getAppSummaries()` will sort them into.
                let popularity = Float(apps.count - index)
                // The older half sells less than the recent half, so the summary's change arrows
                // point up.
                let growth: Float = day < -days/2 ? 0.82 : 1
                guard let date = Calendar.current.date(byAdding: .day, value: day, to: .now),
                      let countryCode = countries.randomElement(using: &generator),
                      let device = devices.randomElement(using: &generator) else { continue }
                entries.append(Event(
                    appTitle: app.name,
                    appSKU: app.sku,
                    units: Int((popularity * growth * Float.random(in: 8...14, using: &generator)).rounded()),
                    proceeds: Float(app.price) * Float.random(in: 0.5...0.9, using: &generator),
                    date: date,
                    countryCode: countryCode,
                    device: device,
                    appIdentifier: app.appleID,
                    type: .download))
            }
        }

        // Income beyond paid downloads, for the income pie: a subscription, in-app purchases, and
        // ads. A generator of its own, so the downloads above stay as they were.
        var incomeGenerator = SeededGenerator(seed: 20261029)
        let incomeSources: [(app: ACApp, type: EventType, proceeds: ClosedRange<Float>)] = [
            (.demo1, .subscription, 20...34),
            (.demo2, .iap, 8...16),
            (.demo3, .ad, 4...9),
        ]
        for day in -days...0 {
            guard let date = Calendar.current.date(byAdding: .day, value: day, to: .now) else { continue }
            for source in incomeSources {
                entries.append(Event(
                    appTitle: source.app.name,
                    appSKU: source.app.sku,
                    units: 1,
                    proceeds: Float.random(in: source.proceeds, using: &incomeGenerator),
                    date: date,
                    countryCode: "US",
                    device: source.type == .ad ? "" : "iPhone",
                    appIdentifier: source.app.appleID,
                    type: source.type))
            }
        }

        for app in apps {
            Task {
                await app.saveIcon()
            }
        }
        
        return ACData(entries: entries, currency: .USD, apps: apps)
    }
}

/// A reproducible generator, so `ACData.example` is the same dataset on every launch.
/// SplitMix64: short enough to read, and more than good enough for demo numbers.
/// One day's figure, for a line chart.
struct DailyValue: Hashable {
    let date: Date
    let value: Double
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// `Sendable` and the `String` raw value are declared here rather than alongside the `AppEnum`
// conformance in the Intents folder, which Swift requires to be in the type's own file.
enum InfoType: String, CaseIterable, Sendable {
    case proceeds, downloads, updates, iap

    var systemImage: String {
        switch self {
        case .proceeds:
            return "dollarsign.circle"
        case .downloads:
            return "square.and.arrow.down"
        case .updates:
            return "arrow.triangle.2.circlepath"
        case .iap:
            return "cart"
        }
    }
}
