import AppIntents
import Foundation

/// The window an intent reports on.
///
/// Each period is compared against the window of equal length immediately before it — the same
/// shape as the home screen's 30-days-vs-the-30-before-those summary.
enum SalesPeriod: String, AppEnum {
    case today
    case yesterday
    case last7Days
    case last30Days

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Period" }
    // Every title is a literal here rather than mapped out of a `switch`: the App Intents metadata
    // exporter reads this dictionary at build time and rejects anything it cannot resolve itself.
    static var caseDisplayRepresentations: [SalesPeriod: DisplayRepresentation] {
        [
            .today: DisplayRepresentation(title: "Today"),
            .yesterday: DisplayRepresentation(title: "Yesterday"),
            .last7Days: DisplayRepresentation(title: "Last 7 Days"),
            .last30Days: DisplayRepresentation(title: "Last 30 Days"),
        ]
    }

    /// The period's name for dialog text, read back out of the display representations so the
    /// wording has one home.
    var title: LocalizedStringResource {
        SalesPeriod.caseDisplayRepresentations[self]?.title ?? "\(rawValue)"
    }

    /// The half-open range of report dates this period covers.
    ///
    /// App Store Connect publishes a day's report the following morning, so `today` is usually still
    /// empty and `yesterday` is the freshest complete day.
    var dateRange: Range<Date> {
        let calendar = Calendar.autoupdatingCurrent
        let startOfToday = calendar.startOfDay(for: .now)

        switch self {
        case .today:
            return startOfToday..<max(startOfToday, .now)
        case .yesterday:
            return calendar.date(byAdding: .day, value: -1, to: startOfToday, default: startOfToday)..<startOfToday
        case .last7Days, .last30Days:
            return calendar.date(byAdding: .day, value: -days, to: .now, default: .now)..<Date.now
        }
    }

    /// The window of the same length immediately before `dateRange`, which every intent reports the
    /// change against. Stepped by calendar days rather than by subtracting an interval, so a
    /// daylight-saving boundary cannot pull a day in or out of the comparison.
    var previousDateRange: Range<Date> {
        let calendar = Calendar.autoupdatingCurrent
        let range = dateRange

        let start = calendar.date(byAdding: .day, value: -days, to: range.lowerBound, default: range.lowerBound)
        let end = calendar.date(byAdding: .day, value: -days, to: range.upperBound, default: range.upperBound)

        return start..<end
    }

    private var days: Int {
        switch self {
        case .today, .yesterday:
            return 1
        case .last7Days:
            return 7
        case .last30Days:
            return 30
        }
    }
}

private extension Calendar {
    /// `date(byAdding:value:to:)` without the optional, which no period here can actually hit.
    func date(byAdding component: Calendar.Component, value: Int, to date: Date, default fallback: Date) -> Date {
        self.date(byAdding: component, value: value, to: date) ?? fallback
    }
}

/// Exposes the app's existing metric split to Shortcuts, rather than keeping a second enum in step
/// with it.
extension InfoType: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Metric" }
    static var caseDisplayRepresentations: [InfoType: DisplayRepresentation] {
        [
            .proceeds: DisplayRepresentation(title: "Proceeds", image: .init(systemName: "dollarsign.circle")),
            .downloads: DisplayRepresentation(title: "Downloads", image: .init(systemName: "square.and.arrow.down")),
            .updates: DisplayRepresentation(title: "Updates", image: .init(systemName: "arrow.triangle.2.circlepath")),
            .iap: DisplayRepresentation(title: "In-App Purchases", image: .init(systemName: "cart")),
        ]
    }

    /// The metric's name for dialog text. See `SalesPeriod.title`.
    var title: LocalizedStringResource {
        InfoType.caseDisplayRepresentations[self]?.title ?? "\(rawValue)"
    }
}

/// Lets an `APIError` surface in Shortcuts with the same wording the app shows.
extension APIError: CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        "\(errorDescription ?? String(localized: "An unknown error occurred."))"
    }
}

enum SalesIntentError: Error, CustomLocalizedStringResourceConvertible {
    /// Nothing in the Keychain to fetch against — the app's own "No Account" empty state.
    case noAccount

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noAccount:
            return "Add an App Store Connect account in App Sales first."
        }
    }
}

/// The one place the intents resolve an account and fetch its data.
///
/// Everything goes through `AppStoreConnectAPI.getData`, so both cache layers apply — the five-minute
/// in-memory memoization and the on-disk cache in the App Group — and the demo account still
/// short-circuits to `ACData.example`.
enum SalesIntentData {

    /// The account the intent was given, or the one the app is currently showing.
    static func resolveAccount(_ requested: Account?) throws -> Account {
        if let requested {
            return requested
        }

        let manager = AccountManager.shared
        let selectedID = UserDefaults.shared?.string(forKey: UserDefaults.Key.homeSelectedKey) ?? ""
        guard let account = manager.getApiKey(apiKeyId: selectedID) ?? manager.accounts.first else {
            throw SalesIntentError.noAccount
        }
        return account
    }

    /// Sales for an account, converted to the reader's own currency the way the home screen does.
    static func data(for account: Account) async throws -> ACData {
        let api = AppStoreConnectAPI(apiKey: account)
        return try await api.getData(currency: Currency(rawValue: Locale.autoupdatingCurrent.currency?.identifier ?? ""))
    }

    /// Both steps, for the common case where the caller only wants the numbers.
    static func data(for requested: Account?) async throws -> ACData {
        try await data(for: resolveAccount(requested))
    }
}

extension InfoType {
    /// A metric's total, written the way the app writes it: proceeds as money, the rest as counts.
    func format(_ value: Double, currency: Currency) -> String {
        switch self {
        case .proceeds:
            return value.formatted(.currency(code: currency.rawValue))
        case .downloads, .updates, .iap:
            return Int(value).formatted()
        }
    }
}
